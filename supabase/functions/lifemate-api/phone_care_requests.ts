import { hashContactPoint } from "../_shared/contact_point_crypto.ts";
import { getLifeMateSql } from "./database_client.ts";
import {
  maskIranianMobileE164,
  normalizeIranianMobileE164,
} from "./iran_phone.ts";
import { createHmac } from "./security.ts";
import { ApiError, requiredText } from "./validation.ts";

type Row = Record<string, any>;

type CareRequestIdentity = {
  appUserId: string;
  auth: { email: string | null };
};

type RelationshipParticipants = {
  patientPersonId: string;
  caregiverPersonId: string;
};

type SelfContext = {
  accountId: string;
  personId: string;
};

const requestContactType = "CareRequestPhone";
const caregiverConsentVersion = "care-caregiver-request-v1";
const patientConsentVersion = "care-patient-consent-v1";

export function createPhoneCareRequestStore(
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

    const rawPhone = requiredText(body.contact, "contact", 64);
    const phone = normalizeIranianMobileE164(rawPhone);
    if (!phone) {
      throw new ApiError(
        400,
        "invalid_contact",
        "A valid Iranian mobile number is required.",
      );
    }
    const contactHash = await hashContactPoint(
      contactHashingSecret,
      "Phone",
      phone,
    );
    const caller = await requireSelfContext(sql, identity.appUserId);
    const targetRows = await sql`
      select cp.account_id::text as account_id,
             links.person_id::text as person_id
      from identity.contact_points cp
      join identity.accounts a
        on a.id=cp.account_id and a.status='Active'
      join core.account_person_links links
        on links.account_id=cp.account_id
       and links.link_type='Self'
       and links.status='Active'
      where cp.kind='Phone'
        and cp.status='Verified'
        and cp.normalized_value_hash=${contactHash}
      order by cp.updated_at_utc desc,cp.id
      limit 2
    `;
    const target = targetRows.length === 1 ? targetRows[0] : null;
    if (
      target &&
      (target.account_id === caller.accountId ||
        target.person_id === caller.personId)
    ) {
      throw new ApiError(
        400,
        "self_care_request_not_allowed",
        "You cannot request care access to your own account.",
      );
    }

    const now = new Date();
    const expires = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    const id = crypto.randomUUID();
    const tokenHash = await hmac(`phone-care-request-row:${id}`);
    const contactHint = maskIranianMobileE164(phone);

    return await sql.begin(async (tx: any) => {
      await tx`
        update lifemate.care_invitations
        set status='Expired'
        where inviter_user_id=${identity.appUserId}::uuid
          and contact_type=${requestContactType}
          and contact_hash=${contactHash}
          and status='Pending'
          and expires_at_utc <= now()
      `;

      const targetAccountId = target?.account_id ?? null;
      const inserted = await tx`
        insert into lifemate.care_invitations(
          id,inviter_user_id,contact_type,contact_hash,contact_hint,
          token_hash,patient_consent_version,status,expires_at_utc,
          responded_by_user_id,responded_at_utc,revoked_at_utc,created_at_utc,
          target_account_id
        ) values(
          ${id}::uuid,${identity.appUserId}::uuid,${requestContactType},
          ${contactHash},${contactHint},${tokenHash},${caregiverConsentVersion},
          'Pending',${expires},null,null,null,${now},${targetAccountId}::uuid
        )
        on conflict (inviter_user_id,contact_type,contact_hash)
          where contact_type='CareRequestPhone' and status='Pending'
        do nothing
        returning *
      `;
      if (!inserted[0]) {
        const pending = await tx`
          select *
          from lifemate.care_invitations
          where inviter_user_id=${identity.appUserId}::uuid
            and contact_type=${requestContactType}
            and contact_hash=${contactHash}
            and status='Pending'
          order by created_at_utc desc
          limit 1
        `;
        if (!pending[0]) {
          throw new ApiError(
            409,
            "care_request_retry_conflict",
            "The care request could not be resolved safely.",
          );
        }
        return mapRequest(pending[0]);
      }

      await insertAudit(
        tx,
        identity.appUserId,
        "care_request.created",
        "care_invitation",
        inserted[0].id,
      );
      return mapRequest(inserted[0]);
    });
  }

  async function listOutgoing(
    caregiverUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const rows = await sql`
      select * from lifemate.care_invitations
      where inviter_user_id=${caregiverUserId}::uuid
        and contact_type=${requestContactType}
      order by created_at_utc desc
      limit 100
    `;
    return rows.map(mapRequest);
  }

  async function listIncoming(
    identity: CareRequestIdentity,
  ): Promise<Record<string, unknown>[]> {
    const self = await requireSelfContext(sql, identity.appUserId);
    const rows = await sql`
      select i.*,p.display_name as requester_display_name,
             p.avatar_key as requester_avatar_key
      from lifemate.care_invitations i
      join lifemate.user_profiles p on p.user_id=i.inviter_user_id
      where i.contact_type=${requestContactType}
        and i.target_account_id=${self.accountId}::uuid
        and i.status='Pending'
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

  async function respondIfPhone(
    identity: CareRequestIdentity,
    requestId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown> | null> {
    const existing = await sql`
      select id from lifemate.care_invitations
      where id=${requestId}::uuid and contact_type=${requestContactType}
      limit 1
    `;
    if (!existing[0]) return null;

    const action = requiredText(body.action, "action", 16).toLowerCase();
    if (action !== "accept" && action !== "reject") {
      throw new ApiError(
        400,
        "invalid_care_request_action",
        "Action is invalid.",
      );
    }
    if (
      action === "accept" &&
      (body.confirmConsent !== true ||
        body.consentVersion !== patientConsentVersion)
    ) {
      throw new ApiError(
        400,
        "patient_consent_required",
        "Patient consent is required to approve care access.",
      );
    }
    const self = await requireSelfContext(sql, identity.appUserId);
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const rows = await tx`
        select * from lifemate.care_invitations
        where id=${requestId}::uuid and contact_type=${requestContactType}
        for update
      `;
      const request = rows[0];
      if (!request || request.target_account_id !== self.accountId) {
        throw new ApiError(
          404,
          "care_request_not_found",
          "Care request was not found.",
        );
      }
      if (request.status !== "Pending") {
        throw new ApiError(
          409,
          "care_request_not_pending",
          "Care request is no longer pending.",
        );
      }
      if (new Date(request.expires_at_utc) <= now) {
        await tx`
          update lifemate.care_invitations set status='Expired'
          where id=${request.id}::uuid
        `;
        throw new ApiError(
          410,
          "care_request_expired",
          "Care request has expired.",
        );
      }
      if (request.inviter_user_id === identity.appUserId) {
        throw new ApiError(
          400,
          "self_care_request_not_allowed",
          "Self care is not allowed.",
        );
      }

      if (action === "reject") {
        await tx`
          update lifemate.care_invitations
          set status='Rejected',responded_by_user_id=${identity.appUserId}::uuid,
              responded_at_utc=${now}
          where id=${request.id}::uuid
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

      const participants = await requireRelationshipParticipants(
        tx,
        identity.appUserId,
        request.inviter_user_id,
      );
      const active = await tx`
        select * from lifemate.care_relationships
        where patient_person_id=${participants.patientPersonId}::uuid
          and caregiver_person_id=${participants.caregiverPersonId}::uuid
          and status='Active'
        limit 1
      `;
      let relationship = active[0];
      if (!relationship) {
        const relationshipRows = await tx`
          insert into lifemate.care_relationships(
            id,patient_user_id,caregiver_user_id,status,
            patient_consent_version,patient_consented_at_utc,
            caregiver_consent_version,caregiver_consented_at_utc,
            revoked_by_user_id,revoked_at_utc,created_at_utc,updated_at_utc
          ) values(
            ${crypto.randomUUID()}::uuid,${identity.appUserId}::uuid,
            ${request.inviter_user_id}::uuid,'Active',${patientConsentVersion},
            ${now},${caregiverConsentVersion},${request.created_at_utc},
            null,null,${now},${now}
          ) returning *
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
        set status='Accepted',responded_by_user_id=${identity.appUserId}::uuid,
            responded_at_utc=${now}
        where id=${request.id}::uuid
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

  async function cancelIfPhone(
    caregiverUserId: string,
    requestId: string,
  ): Promise<boolean> {
    const existing = await sql`
      select id from lifemate.care_invitations
      where id=${requestId}::uuid and contact_type=${requestContactType}
      limit 1
    `;
    if (!existing[0]) return false;
    await sql.begin(async (tx: any) => {
      const rows = await tx`
        select * from lifemate.care_invitations
        where id=${requestId}::uuid
          and inviter_user_id=${caregiverUserId}::uuid
          and contact_type=${requestContactType}
        for update
      `;
      const request = rows[0];
      if (!request) {
        throw new ApiError(
          404,
          "care_request_not_found",
          "Care request was not found.",
        );
      }
      if (request.status !== "Pending") return;
      await tx`
        update lifemate.care_invitations
        set status='Revoked',revoked_at_utc=now()
        where id=${request.id}::uuid
      `;
      await insertAudit(
        tx,
        caregiverUserId,
        "care_request.revoked",
        "care_invitation",
        request.id,
      );
    });
    return true;
  }

  function mapRequest(row: Row): Record<string, unknown> {
    const expired = row.status === "Pending" &&
      new Date(row.expires_at_utc) <= new Date();
    return {
      id: row.id,
      contactType: "phone",
      contactHint: row.contact_hint,
      status: expired ? "expired" : String(row.status).toLowerCase(),
      expiresAtUtc: new Date(row.expires_at_utc).toISOString(),
      createdAtUtc: new Date(row.created_at_utc).toISOString(),
    };
  }

  return {
    create,
    listOutgoing,
    listIncoming,
    respondIfPhone,
    cancelIfPhone,
  };
}

async function requireSelfContext(
  connection: any,
  appUserId: string,
): Promise<SelfContext> {
  const rows = await connection`
    select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
             as account_id,
           core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
             as person_id
  `;
  const accountId = rows[0]?.account_id;
  const personId = rows[0]?.person_id;
  if (typeof accountId !== "string" || typeof personId !== "string") {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate identity mapping is unavailable.",
    );
  }
  return { accountId, personId };
}

async function requireRelationshipParticipants(
  connection: any,
  patientUserId: string,
  caregiverUserId: string,
): Promise<RelationshipParticipants> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${patientUserId}::uuid)::text
             as patient_person_id,
           core.self_person_id_for_legacy_app_user(${caregiverUserId}::uuid)::text
             as caregiver_person_id
  `;
  const patientPersonId = rows[0]?.patient_person_id;
  const caregiverPersonId = rows[0]?.caregiver_person_id;
  if (
    typeof patientPersonId !== "string" || typeof caregiverPersonId !== "string"
  ) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  if (patientPersonId === caregiverPersonId) {
    throw new ApiError(
      400,
      "self_care_request_not_allowed",
      "Self care is not allowed.",
    );
  }
  return { patientPersonId, caregiverPersonId };
}

async function insertAudit(
  connection: any,
  actorUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs(
      id,actor_user_id,action,resource_type,resource_id,metadata_json,created_at_utc
    ) values(
      ${crypto.randomUUID()}::uuid,${actorUserId}::uuid,${action},${resourceType},
      ${resourceId},null,now()
    )
  `;
}
