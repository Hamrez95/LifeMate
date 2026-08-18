import { getLifeMateSql } from "./database_client.ts";
import { createHmac, timingSafeEqual } from "./security.ts";
import { ApiError, requiredText } from "./validation.ts";

type Row = Record<string, any>;

type InvitationIdentity = {
  appUserId: string;
  auth: { email: string | null };
};

type RelationshipParticipants = {
  patientPersonId: string;
  caregiverPersonId: string;
};

export function createPersonInvitationAcceptanceStore(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const sql = getLifeMateSql(databaseUrl);
  const hmac = createHmac(contactHashingSecret);

  async function acceptInvitation(
    identity: InvitationIdentity,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    if (
      body.confirmConsent !== true ||
      body.consentVersion !== "care-caregiver-consent-v1"
    ) {
      throw new ApiError(
        400,
        "caregiver_consent_required",
        "Caregiver consent is required.",
      );
    }

    const token = requiredText(body.token, "token", 512);
    const tokenHash = await hmac(`token:${token}`);
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const invitationRows = await tx`
        select *
        from lifemate.care_invitations
        where token_hash = ${tokenHash}
        for update
      `;
      const invitation = invitationRows[0];
      if (!invitation) {
        throw new ApiError(
          404,
          "invitation_not_found",
          "Invitation is invalid.",
        );
      }
      if (String(invitation.contact_type).toLowerCase() === "phone") {
        throw new ApiError(
          409,
          "phone_invitation_delegate_required",
          "Phone invitation must use the phone acceptance path.",
        );
      }

      const participants = await requireRelationshipParticipants(
        tx,
        invitation.inviter_user_id,
        identity.appUserId,
      );

      if (
        invitation.status === "Accepted" &&
        invitation.responded_by_user_id === identity.appUserId
      ) {
        const existing = await activeRelationship(tx, participants);
        if (existing) return await mapRelationship(tx, existing);
      }
      if (invitation.status !== "Pending") {
        throw new ApiError(
          409,
          "invitation_not_pending",
          "Invitation is no longer pending.",
        );
      }
      if (new Date(invitation.expires_at_utc) <= now) {
        await tx`
          update lifemate.care_invitations
          set status = 'Expired'
          where id = ${invitation.id}
        `;
        throw new ApiError(
          410,
          "invitation_expired",
          "Invitation has expired.",
        );
      }

      if (String(invitation.contact_type).toLowerCase() !== "qr") {
        if (!identity.auth.email) {
          throw new ApiError(
            403,
            "invitation_contact_mismatch",
            "Signed-in email is required.",
          );
        }
        const contactHash = await hmac(
          `contact:${identity.auth.email.toLowerCase()}`,
        );
        if (!timingSafeEqual(invitation.contact_hash, contactHash)) {
          throw new ApiError(
            403,
            "invitation_contact_mismatch",
            "Invitation belongs to another account.",
          );
        }
      }

      const active = await activeRelationship(tx, participants);
      if (active) return await mapRelationship(tx, active);

      await tx`
        update lifemate.care_invitations
        set status = 'Accepted', responded_by_user_id = ${identity.appUserId},
            responded_at_utc = ${now}
        where id = ${invitation.id}
      `;
      const relationshipId = crypto.randomUUID();
      const relationshipRows = await tx`
        insert into lifemate.care_relationships
          (id, patient_user_id, caregiver_user_id, status,
           patient_consent_version, patient_consented_at_utc,
           caregiver_consent_version, caregiver_consented_at_utc,
           revoked_by_user_id, revoked_at_utc, created_at_utc, updated_at_utc)
        values
          (${relationshipId}::uuid, ${invitation.inviter_user_id}::uuid,
           ${identity.appUserId}::uuid, 'Active',
           ${invitation.patient_consent_version}, ${invitation.created_at_utc},
           'care-caregiver-consent-v1', ${now}, null, null, ${now}, ${now})
        returning *
      `;
      await insertAudit(
        tx,
        identity.appUserId,
        "care_invitation.accepted",
        "care_invitation",
        invitation.id,
      );
      await insertAudit(
        tx,
        identity.appUserId,
        "care_relationship.created",
        "care_relationship",
        relationshipId,
      );
      return await mapRelationship(tx, relationshipRows[0]);
    });
  }

  async function activeRelationship(
    connection: any,
    participants: RelationshipParticipants,
  ): Promise<Row | null> {
    const rows = await connection`
      select *
      from lifemate.care_relationships
      where patient_person_id = ${participants.patientPersonId}::uuid
        and caregiver_person_id = ${participants.caregiverPersonId}::uuid
        and status = 'Active'
      order by created_at_utc desc
      limit 1
    `;
    return rows[0] ?? null;
  }

  async function mapRelationship(
    connection: any,
    relationship: Row,
  ): Promise<Record<string, unknown>> {
    const names = await connection`
      select user_id, display_name
      from lifemate.user_profiles
      where user_id in ${
      sql([
        relationship.patient_user_id,
        relationship.caregiver_user_id,
      ])
    }
    `;
    const byId = new Map(
      names.map((row: Row) => [row.user_id, row.display_name]),
    );
    return {
      id: relationship.id,
      patientUserId: relationship.patient_user_id,
      patientDisplayName: byId.get(relationship.patient_user_id) ??
        "LifeMate User",
      caregiverUserId: relationship.caregiver_user_id,
      caregiverDisplayName: byId.get(relationship.caregiver_user_id) ??
        "LifeMate User",
      status: String(relationship.status).toLowerCase(),
      canViewWomenCalendar: relationship.can_view_women_calendar === true,
      patientConsentedAtUtc: iso(relationship.patient_consented_at_utc),
      caregiverConsentedAtUtc: iso(relationship.caregiver_consented_at_utc),
      revokedAtUtc: relationship.revoked_at_utc == null
        ? null
        : iso(relationship.revoked_at_utc),
      createdAtUtc: iso(relationship.created_at_utc),
    };
  }

  return { acceptInvitation };
}

async function requireRelationshipParticipants(
  connection: any,
  patientUserId: string,
  caregiverUserId: string,
): Promise<RelationshipParticipants> {
  const rows = await connection`
    select
      core.self_person_id_for_legacy_app_user(${patientUserId}::uuid)::text
        as patient_person_id,
      core.self_person_id_for_legacy_app_user(${caregiverUserId}::uuid)::text
        as caregiver_person_id
  `;
  const patientPersonId = rows[0]?.patient_person_id;
  const caregiverPersonId = rows[0]?.caregiver_person_id;
  if (
    typeof patientPersonId !== "string" || patientPersonId.length === 0 ||
    typeof caregiverPersonId !== "string" || caregiverPersonId.length === 0
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
      "self_invitation_not_allowed",
      "You cannot accept a care invitation for your own person.",
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
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}, ${actorUserId}::uuid, ${action}, ${resourceType},
       ${resourceId}::uuid, null, now())
  `;
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
