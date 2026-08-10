import { getLifeMateSql } from "./database_client.ts";
import { createHmac, createToken, maskEmail } from "./security.ts";
import { ApiError, requiredText } from "./validation.ts";

type Row = Record<string, any>;

type CareRequestIdentity = {
  appUserId: string;
  auth: { email: string | null };
};

const requestContactType = "CareRequestEmail";
const caregiverConsentVersion = "care-caregiver-request-v1";
const patientConsentVersion = "care-patient-consent-v1";

export function createCareRequestStore(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const sql = getLifeMateSql(databaseUrl);
  const hmac = createHmac(contactHashingSecret);

  async function create(
    identity: CareRequestIdentity,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    if (
      body.confirmConsent !== true ||
      body.consentVersion !== caregiverConsentVersion
    ) {
      throw new ApiError(
        400,
        "caregiver_request_consent_required",
        "Caregiver request consent is required.",
      );
    }

    const email = requiredText(body.contact, "contact", 320).toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new ApiError(400, "invalid_contact", "A valid email is required.");
    }
    if (identity.auth.email?.toLowerCase() === email) {
      throw new ApiError(
        400,
        "self_care_request_not_allowed",
        "You cannot request care access to your own account.",
      );
    }

    const targetRows = await sql`
      select u.id, p.display_name
      from lifemate.app_users u
      join lifemate.user_profiles p on p.user_id = u.id
      where u.status = 'Active' and lower(p.email) = ${email}
      limit 1
    `;
    const target = targetRows[0];
    if (!target) {
      throw new ApiError(
        404,
        "care_request_target_not_found",
        "No active WellMate account was found for this email.",
      );
    }

    const active = await sql`
      select id
      from lifemate.care_relationships
      where patient_user_id = ${target.id}
        and caregiver_user_id = ${identity.appUserId}
        and status = 'Active'
      limit 1
    `;
    if (active[0]) {
      throw new ApiError(
        409,
        "care_relationship_already_active",
        "Care access is already active for this person.",
      );
    }

    const contactHash = await hmac(`contact:${email}`);
    const now = new Date();
    const expires = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    const tokenHash = await hmac(`care-request:${createToken()}`);
    const id = crypto.randomUUID();

    return await sql.begin(async (tx: any) => {
      await tx`
        update lifemate.care_invitations
        set status = 'Expired'
        where inviter_user_id = ${identity.appUserId}
          and contact_type = ${requestContactType}
          and contact_hash = ${contactHash}
          and status = 'Pending'
          and expires_at_utc <= now()
      `;
      const pending = await tx`
        select id
        from lifemate.care_invitations
        where inviter_user_id = ${identity.appUserId}
          and contact_type = ${requestContactType}
          and contact_hash = ${contactHash}
          and status = 'Pending'
        limit 1
      `;
      if (pending[0]) {
        throw new ApiError(
          409,
          "care_request_already_pending",
          "A care request is already pending for this person.",
        );
      }

      await tx`
        insert into lifemate.care_invitations
          (id, inviter_user_id, contact_type, contact_hash, contact_hint,
           token_hash, patient_consent_version, status, expires_at_utc,
           responded_by_user_id, responded_at_utc, revoked_at_utc, created_at_utc)
        values
          (${id}, ${identity.appUserId}, ${requestContactType}, ${contactHash},
           ${maskEmail(email)}, ${tokenHash}, ${caregiverConsentVersion},
           'Pending', ${expires}, null, null, null, ${now})
      `;
      await insertAudit(
        tx,
        identity.appUserId,
        "care_request.created",
        "care_invitation",
        id,
      );
      return {
        id,
        contactType: "email",
        contactHint: maskEmail(email),
        targetDisplayName: target.display_name,
        status: "pending",
        expiresAtUtc: expires.toISOString(),
        createdAtUtc: now.toISOString(),
      };
    });
  }

  async function listOutgoing(
    caregiverUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const rows = await sql`
      select *
      from lifemate.care_invitations
      where inviter_user_id = ${caregiverUserId}
        and contact_type = ${requestContactType}
      order by created_at_utc desc
      limit 100
    `;
    return rows.map(mapRequest);
  }

  async function listIncoming(
    identity: CareRequestIdentity,
  ): Promise<Record<string, unknown>[]> {
    const email = identity.auth.email?.trim().toLowerCase();
    if (!email) return [];
    const contactHash = await hmac(`contact:${email}`);
    const rows = await sql`
      select i.*, p.display_name as requester_display_name, p.avatar_key as requester_avatar_key
      from lifemate.care_invitations i
      join lifemate.user_profiles p on p.user_id = i.inviter_user_id
      where i.contact_type = ${requestContactType}
        and i.contact_hash = ${contactHash}
        and i.status = 'Pending'
        and i.expires_at_utc > now()
      order by i.created_at_utc desc
      limit 50
    `;
    return rows.map((row: Row) => ({
      ...mapRequest(row),
      requesterUserId: row.inviter_user_id,
      requesterDisplayName: row.requester_display_name,
      requesterAvatarKey: row.requester_avatar_key ?? "person_blue",
    }));
  }

  async function respond(
    identity: CareRequestIdentity,
    requestId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const action = requiredText(body.action, "action", 16).toLowerCase();
    if (action !== "accept" && action !== "reject") {
      throw new ApiError(400, "invalid_care_request_action", "Action is invalid.");
    }
    if (
      action === "accept" &&
      (body.confirmConsent !== true || body.consentVersion !== patientConsentVersion)
    ) {
      throw new ApiError(
        400,
        "patient_consent_required",
        "Patient consent is required to approve care access.",
      );
    }
    const email = identity.auth.email?.trim().toLowerCase();
    if (!email) {
      throw new ApiError(
        403,
        "care_request_contact_mismatch",
        "A verified account email is required.",
      );
    }
    const contactHash = await hmac(`contact:${email}`);
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const rows = await tx`
        select *
        from lifemate.care_invitations
        where id = ${requestId}::uuid
          and contact_type = ${requestContactType}
        for update
      `;
      const request = rows[0];
      if (!request || request.contact_hash !== contactHash) {
        throw new ApiError(404, "care_request_not_found", "Care request was not found.");
      }
      if (request.status !== "Pending") {
        throw new ApiError(409, "care_request_not_pending", "Care request is no longer pending.");
      }
      if (new Date(request.expires_at_utc) <= now) {
        await tx`
          update lifemate.care_invitations set status = 'Expired'
          where id = ${request.id}
        `;
        throw new ApiError(410, "care_request_expired", "Care request has expired.");
      }
      if (request.inviter_user_id === identity.appUserId) {
        throw new ApiError(400, "self_care_request_not_allowed", "Self care is not allowed.");
      }

      if (action === "reject") {
        await tx`
          update lifemate.care_invitations
          set status = 'Rejected', responded_by_user_id = ${identity.appUserId},
              responded_at_utc = ${now}
          where id = ${request.id}
        `;
        await insertAudit(
          tx,
          identity.appUserId,
          "care_request.rejected",
          "care_invitation",
          request.id,
        );
        return { id: request.id, status: "rejected" };
      }

      const active = await tx`
        select *
        from lifemate.care_relationships
        where patient_user_id = ${identity.appUserId}
          and caregiver_user_id = ${request.inviter_user_id}
          and status = 'Active'
        limit 1
      `;
      let relationship = active[0];
      if (!relationship) {
        const relationshipRows = await tx`
          insert into lifemate.care_relationships
            (id, patient_user_id, caregiver_user_id, status,
             patient_consent_version, patient_consented_at_utc,
             caregiver_consent_version, caregiver_consented_at_utc,
             revoked_by_user_id, revoked_at_utc, created_at_utc, updated_at_utc)
          values
            (${crypto.randomUUID()}, ${identity.appUserId}, ${request.inviter_user_id},
             'Active', ${patientConsentVersion}, ${now}, ${caregiverConsentVersion},
             ${request.created_at_utc}, null, null, ${now}, ${now})
          returning *
        `;
        relationship = relationshipRows[0];
        await insertAudit(
          tx,
          identity.appUserId,
          "care_relationship.created_from_request",
          "care_relationship",
          relationship.id,
        );
      }
      await tx`
        update lifemate.care_invitations
        set status = 'Accepted', responded_by_user_id = ${identity.appUserId},
            responded_at_utc = ${now}
        where id = ${request.id}
      `;
      await insertAudit(
        tx,
        identity.appUserId,
        "care_request.accepted",
        "care_invitation",
        request.id,
      );
      return {
        id: request.id,
        status: "accepted",
        relationshipId: relationship.id,
      };
    });
  }

  async function cancel(caregiverUserId: string, requestId: string): Promise<void> {
    await sql.begin(async (tx: any) => {
      const rows = await tx`
        select * from lifemate.care_invitations
        where id = ${requestId}::uuid
          and inviter_user_id = ${caregiverUserId}
          and contact_type = ${requestContactType}
        for update
      `;
      const request = rows[0];
      if (!request) {
        throw new ApiError(404, "care_request_not_found", "Care request was not found.");
      }
      if (request.status !== "Pending") return;
      await tx`
        update lifemate.care_invitations
        set status = 'Revoked', revoked_at_utc = now()
        where id = ${request.id}
      `;
      await insertAudit(
        tx,
        caregiverUserId,
        "care_request.revoked",
        "care_invitation",
        request.id,
      );
    });
  }

  async function insertAudit(
    connection: any,
    actorUserId: string,
    action: string,
    resourceType: string,
    resourceId: string,
  ): Promise<void> {
    await connection`
      insert into lifemate.audit_logs
        (id, actor_user_id, action, resource_type, resource_id, metadata_json, created_at_utc)
      values
        (${crypto.randomUUID()}, ${actorUserId}, ${action}, ${resourceType},
         ${resourceId}, null, now())
    `;
  }

  function mapRequest(row: Row): Record<string, unknown> {
    const expired = row.status === "Pending" && new Date(row.expires_at_utc) <= new Date();
    return {
      id: row.id,
      contactType: "email",
      contactHint: row.contact_hint,
      status: expired ? "expired" : String(row.status).toLowerCase(),
      expiresAtUtc: new Date(row.expires_at_utc).toISOString(),
      createdAtUtc: new Date(row.created_at_utc).toISOString(),
    };
  }

  return { create, listOutgoing, listIncoming, respond, cancel };
}
