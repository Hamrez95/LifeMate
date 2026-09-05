import { getLifeMateSql, type LifeMateSql } from "./database_client.ts";
import {
  maskIranianMobileE164,
  normalizeIranianMobileE164,
} from "./iran_phone.ts";
import {
  normalizeRelationshipPresentationPatch,
  normalizeRelationshipType,
} from "./relationship_presentation.ts";
import { createHmac, timingSafeEqual } from "./security.ts";
import { ApiError, requiredText } from "./validation.ts";

type Sql = LifeMateSql;
type Row = Record<string, any>;

type RelationshipParticipants = {
  patientPersonId: string;
  caregiverPersonId: string;
};

export type PhoneInvitationIdentity = {
  auth: {
    phone: string | null;
    email?: string | null;
  };
  appUserId: string;
};

export type PhoneInvitationDeliveryCallback = (input: {
  phoneE164: string;
  token: string;
}) => Promise<void>;

type LegacyAccept = (
  identity: PhoneInvitationIdentity,
  body: Record<string, unknown>,
) => Promise<Record<string, unknown>>;

export function createPhoneCareInvitationStore(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const sql = getLifeMateSql(databaseUrl);
  const hmac = createHmac(contactHashingSecret);

  async function createPhoneInvitation(
    identity: PhoneInvitationIdentity,
    body: Record<string, unknown>,
    deliver?: PhoneInvitationDeliveryCallback,
  ): Promise<Record<string, unknown>> {
    requirePatientConsent(body);
    const presentation = normalizeRelationshipPresentationPatch({
      relationshipType: body.relationshipType ?? "unknown",
      displayName: body.displayName,
    });
    const rawContact = requiredText(body.contact, "contact", 64);
    const phone = normalizeIranianMobileE164(rawContact);
    if (phone == null) {
      throw new ApiError(
        400,
        "invalid_contact",
        "A valid Iranian mobile number is required.",
      );
    }

    const currentPhone = identity.auth.phone == null
      ? null
      : normalizeIranianMobileE164(identity.auth.phone);
    if (currentPhone != null && currentPhone === phone) {
      throw new ApiError(
        400,
        "self_invitation_not_allowed",
        "You cannot invite yourself.",
      );
    }

    const contactHash = await hmac(`contact:${phone}`);
    const now = new Date();
    const expires = new Date(now.getTime() + 30 * 60 * 1000);
    const token = createPhoneInvitationToken();
    const tokenHash = await hmac(`token:${token}`);
    const hint = maskIranianMobileE164(phone);

    return await sql.begin(async (tx: any) => {
      await tx`
        update lifemate.care_invitations
        set status = 'Expired'
        where inviter_user_id = ${identity.appUserId}
          and contact_hash = ${contactHash}
          and contact_type = 'Phone'
          and status = 'Pending'
          and expires_at_utc <= now()
      `;
      const pending = await tx`
        select id
        from lifemate.care_invitations
        where inviter_user_id = ${identity.appUserId}
          and contact_hash = ${contactHash}
          and contact_type = 'Phone'
          and status = 'Pending'
        limit 1
      `;
      if (pending[0]) {
        throw new ApiError(
          409,
          "invitation_already_pending",
          "An invitation is already pending.",
        );
      }

      const id = crypto.randomUUID();
      await tx`
        insert into lifemate.care_invitations
          (id, inviter_user_id, contact_type, contact_hash, contact_hint,
           token_hash, patient_consent_version, status, expires_at_utc,
           responded_by_user_id, responded_at_utc, revoked_at_utc, created_at_utc,
           relationship_type, inviter_caregiver_display_name)
        values
          (${id}, ${identity.appUserId}, 'Phone', ${contactHash}, ${hint},
           ${tokenHash}, 'care-patient-consent-v1', 'Pending', ${expires},
           null, null, null, ${now}, ${presentation.relationshipType},
           ${presentation.displayName})
      `;

      if (deliver) {
        await deliver({ phoneE164: phone, token });
      }

      await insertAudit(
        tx,
        identity.appUserId,
        "care_invitation.phone_created",
        "care_invitation",
        id,
      );
      return {
        id,
        contactType: "phone",
        contactHint: hint,
        relationshipType: presentation.relationshipType,
        caregiverDisplayName: presentation.displayName,
        token,
        expiresAtUtc: expires.toISOString(),
      };
    });
  }

  async function previewInvitation(
    identity: PhoneInvitationIdentity,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const token = requiredText(body.token, "token", 512);
    const tokenHash = await hmac(`token:${token}`);
    const rows = await sql`
      select i.*, p.display_name as inviter_display_name
      from lifemate.care_invitations i
      left join lifemate.user_profiles p on p.user_id = i.inviter_user_id
      where i.token_hash = ${tokenHash}
      limit 1
    `;
    const invitation = rows[0];
    if (!invitation) {
      throw new ApiError(404, "invitation_not_found", "Invitation is invalid.");
    }
    if (invitation.status !== "Pending") {
      throw new ApiError(
        409,
        "invitation_not_pending",
        "Invitation is no longer pending.",
      );
    }
    if (new Date(invitation.expires_at_utc) <= new Date()) {
      throw new ApiError(410, "invitation_expired", "Invitation has expired.");
    }
    if (invitation.inviter_user_id === identity.appUserId) {
      throw new ApiError(
        400,
        "self_invitation_not_allowed",
        "You cannot accept your own invitation.",
      );
    }

    const contactType = String(invitation.contact_type ?? "").toLowerCase();
    if (contactType === "phone") {
      const currentPhone = identity.auth.phone == null
        ? null
        : normalizeIranianMobileE164(identity.auth.phone);
      if (currentPhone == null) throw contactMismatch();
      const currentContactHash = await hmac(`contact:${currentPhone}`);
      if (!timingSafeEqual(invitation.contact_hash, currentContactHash)) {
        throw contactMismatch();
      }
    } else if (contactType === "email") {
      const email = identity.auth.email?.trim().toLowerCase();
      if (!email) throw contactMismatch();
      const currentContactHash = await hmac(`contact:${email}`);
      if (!timingSafeEqual(invitation.contact_hash, currentContactHash)) {
        throw contactMismatch();
      }
    } else if (contactType !== "qr") {
      throw new ApiError(
        400,
        "unsupported_invitation_contact",
        "Invitation contact type is unsupported.",
      );
    }

    return {
      inviterUserId: invitation.inviter_user_id,
      inviterDisplayName: String(
        invitation.inviter_display_name ?? "LifeMate User",
      ),
      relationshipType: normalizeRelationshipType(invitation.relationship_type),
      contactType,
      expiresAtUtc: iso(invitation.expires_at_utc),
    };
  }

  async function acceptInvitationOrDelegate(
    identity: PhoneInvitationIdentity,
    body: Record<string, unknown>,
    legacyAccept: LegacyAccept,
  ): Promise<Record<string, unknown>> {
    requireCaregiverConsent(body);
    const token = requiredText(body.token, "token", 512);
    const tokenHash = await hmac(`token:${token}`);
    const probe = await sql`
      select contact_type
      from lifemate.care_invitations
      where token_hash = ${tokenHash}
      limit 1
    `;
    if (String(probe[0]?.contact_type ?? "").toLowerCase() !== "phone") {
      return await legacyAccept(identity, body);
    }
    return await acceptPhoneInvitation(identity, tokenHash);
  }

  async function acceptPhoneInvitation(
    identity: PhoneInvitationIdentity,
    tokenHash: string,
  ): Promise<Record<string, unknown>> {
    const currentPhone = identity.auth.phone == null
      ? null
      : normalizeIranianMobileE164(identity.auth.phone);
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const invitations = await tx`
        select *
        from lifemate.care_invitations
        where token_hash = ${tokenHash}
        for update
      `;
      const invitation = invitations[0];
      if (!invitation) {
        throw new ApiError(
          404,
          "invitation_not_found",
          "Invitation is invalid.",
        );
      }

      if (
        invitation.status === "Accepted" &&
        invitation.responded_by_user_id === identity.appUserId
      ) {
        const existing = await activeRelationship(
          tx,
          invitation.inviter_user_id,
          identity.appUserId,
        );
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

      if (currentPhone == null) {
        throw contactMismatch();
      }
      const currentContactHash = await hmac(`contact:${currentPhone}`);
      if (!timingSafeEqual(invitation.contact_hash, currentContactHash)) {
        throw contactMismatch();
      }
      if (invitation.inviter_user_id === identity.appUserId) {
        throw new ApiError(
          400,
          "self_invitation_not_allowed",
          "You cannot accept your own invitation.",
        );
      }

      const existing = await activeRelationship(
        tx,
        invitation.inviter_user_id,
        identity.appUserId,
      );
      if (existing) {
        await tx`
          update lifemate.care_invitations
          set status = 'Accepted', responded_by_user_id = ${identity.appUserId},
              responded_at_utc = ${now}
          where id = ${invitation.id}
        `;
        await insertAudit(
          tx,
          identity.appUserId,
          "care_invitation.accepted",
          "care_invitation",
          invitation.id,
        );
        return await mapRelationship(tx, existing);
      }

      await tx`
        update lifemate.care_invitations
        set status = 'Accepted', responded_by_user_id = ${identity.appUserId},
            responded_at_utc = ${now}
        where id = ${invitation.id}
      `;
      const relationshipId = crypto.randomUUID();
      const relationshipType = normalizeRelationshipType(
        invitation.relationship_type,
      );
      const relationshipRows = await tx`
        insert into lifemate.care_relationships
          (id, patient_user_id, caregiver_user_id, status,
           patient_consent_version, patient_consented_at_utc,
           caregiver_consent_version, caregiver_consented_at_utc,
           revoked_by_user_id, revoked_at_utc, created_at_utc, updated_at_utc,
           relationship_type, patient_relationship_type,
           caregiver_relationship_type, patient_caregiver_display_name)
        values
          (${relationshipId}, ${invitation.inviter_user_id}, ${identity.appUserId},
           'Active', ${invitation.patient_consent_version},
           ${invitation.created_at_utc}, 'care-caregiver-consent-v1', ${now},
           null, null, ${now}, ${now}, ${relationshipType}, ${relationshipType},
           ${relationshipType}, ${invitation.inviter_caregiver_display_name})
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

  return {
    createPhoneInvitation,
    previewInvitation,
    acceptInvitationOrDelegate,
  };

  async function activeRelationship(
    connection: any,
    patientUserId: string,
    caregiverUserId: string,
  ): Promise<Row | null> {
    const participants = await requireRelationshipParticipants(
      connection,
      patientUserId,
      caregiverUserId,
    );
    const rows = await connection`
      select *
      from lifemate.care_relationships
      where patient_person_id = ${participants.patientPersonId}::uuid
        and caregiver_person_id = ${participants.caregiverPersonId}::uuid
        and status = 'Active'
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
      relationshipType: normalizeRelationshipType(
        relationship.relationship_type,
      ),
      presentationType: normalizeRelationshipType(
        relationship.relationship_type,
      ),
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
}

function requirePatientConsent(body: Record<string, unknown>): void {
  if (
    body.confirmConsent !== true ||
    body.consentVersion !== "care-patient-consent-v1"
  ) {
    throw new ApiError(
      400,
      "patient_consent_required",
      "Patient consent is required.",
    );
  }
}

function requireCaregiverConsent(body: Record<string, unknown>): void {
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
}

function contactMismatch(): ApiError {
  return new ApiError(
    403,
    "invitation_contact_mismatch",
    "Invitation belongs to another account.",
  );
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
      "You cannot create a care relationship with your own person.",
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
       ${resourceId}, null, now())
  `;
}

function createPhoneInvitationToken(): string {
  let token = "";
  const buffer = new Uint8Array(16);
  while (token.length < 10) {
    crypto.getRandomValues(buffer);
    for (const value of buffer) {
      if (value >= 250) continue;
      token += String(value % 10);
      if (token.length === 10) break;
    }
  }
  return token;
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
