import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for phone invitation tests.");
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name: "phone invitation is contact-bound one-time consented and privacy-safe",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const suffix = crypto.randomUUID();
    try {
      const patient = await bootstrap(
        db,
        auth(
          `phone-patient-${suffix}`,
          `phone-patient-${suffix}@example.test`,
          "+989121111111",
        ),
        "بیمار تلفنی",
      );
      const caregiver = await bootstrap(
        db,
        auth(
          `phone-caregiver-${suffix}`,
          `phone-caregiver-${suffix}@example.test`,
          "+989351234999",
        ),
        "مراقب تلفنی",
      );
      const unrelated = await bootstrap(
        db,
        auth(
          `phone-unrelated-${suffix}`,
          `phone-unrelated-${suffix}@example.test`,
          "+989361234888",
        ),
        "کاربر نامرتبط",
      );
      const revokedRecipient = await bootstrap(
        db,
        auth(
          `phone-revoked-${suffix}`,
          `phone-revoked-${suffix}@example.test`,
          "+989371234777",
        ),
        "مراقب لغوشده",
      );

      await assertApiError(
        () =>
          db.createPhoneInvitation(patient, {
            contact: "09121111111",
            consentVersion: "care-patient-consent-v1",
            confirmConsent: true,
          }),
        400,
        "self_invitation_not_allowed",
      );

      const invitation = await db.createPhoneInvitation(patient, {
        contact: "۰۹۳۵ ۱۲۳ ۴۹۹۹",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      assertEquals(invitation.contactType, "phone");
      assertEquals(invitation.contactHint, "+98 ••• •• 4999");
      assert(typeof invitation.token === "string");
      assert(!String(invitation.contactHint).includes("09351234999"));

      const stored = await admin`
        select contact_type, contact_hash, contact_hint, token_hash
        from lifemate.care_invitations
        where id = ${String(invitation.id)}
      `;
      assertEquals(stored[0].contact_type, "Phone");
      assertEquals(stored[0].contact_hint, "+98 ••• •• 4999");
      assert(!String(stored[0].contact_hash).includes("09351234999"));
      assert(!String(stored[0].contact_hash).includes("+989351234999"));
      assert(!String(stored[0].token_hash).includes(String(invitation.token)));

      await assertApiError(
        () =>
          db.acceptInvitation(unrelated, {
            token: invitation.token,
            consentVersion: "care-caregiver-consent-v1",
            confirmConsent: true,
          }),
        403,
        "invitation_contact_mismatch",
      );

      const relationship = await db.acceptInvitation(caregiver, {
        token: invitation.token,
        consentVersion: "care-caregiver-consent-v1",
        confirmConsent: true,
      });
      assertEquals(relationship.status, "active");
      assertEquals(relationship.patientUserId, patient.appUserId);
      assertEquals(relationship.caregiverUserId, caregiver.appUserId);

      const replay = await db.acceptInvitation(caregiver, {
        token: invitation.token,
        consentVersion: "care-caregiver-consent-v1",
        confirmConsent: true,
      });
      assertEquals(replay.id, relationship.id);
      assertEquals(replay.status, "active");

      await assertApiError(
        () => db.revokeInvitation(patient.appUserId, invitation.id),
        409,
        "invitation_not_pending",
      );

      const expired = await db.createPhoneInvitation(patient, {
        contact: "+989361234888",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      await admin`
        update lifemate.care_invitations
        set expires_at_utc = now() - interval '1 minute'
        where id = ${String(expired.id)}
      `;
      await assertApiError(
        () =>
          db.acceptInvitation(unrelated, {
            token: expired.token,
            consentVersion: "care-caregiver-consent-v1",
            confirmConsent: true,
          }),
        410,
        "invitation_expired",
      );

      const revoked = await db.createPhoneInvitation(patient, {
        contact: "+989371234777",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      await assertApiError(
        () => db.revokeInvitation(unrelated.appUserId, revoked.id),
        404,
        "invitation_not_found",
      );

      const stillPending = await admin`
        select status
        from lifemate.care_invitations
        where id = ${String(revoked.id)}
      `;
      assertEquals(stillPending[0].status, "Pending");

      await db.revokeInvitation(patient.appUserId, revoked.id);
      // A retry with a fresh HTTP idempotency key must remain harmless and must
      // not duplicate the revoke audit effect.
      await db.revokeInvitation(patient.appUserId, revoked.id);

      const revokedStored = await admin`
        select status, revoked_at_utc
        from lifemate.care_invitations
        where id = ${String(revoked.id)}
      `;
      assertEquals(revokedStored[0].status, "Revoked");
      assert(revokedStored[0].revoked_at_utc instanceof Date);

      const revokeAudits = await admin`
        select metadata_json
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}
          and action = 'care_invitation.revoked'
          and resource_type = 'care_invitation'
          and resource_id = ${String(revoked.id)}
      `;
      assertEquals(revokeAudits.length, 1);
      assertEquals(revokeAudits[0].metadata_json, null);

      await assertApiError(
        () =>
          db.acceptInvitation(revokedRecipient, {
            token: revoked.token,
            consentVersion: "care-caregiver-consent-v1",
            confirmConsent: true,
          }),
        409,
        "invitation_not_pending",
      );

      const audits = await admin`
        select action, metadata_json
        from lifemate.audit_logs
        where resource_type in ('care_invitation', 'care_relationship')
          and (
            actor_user_id = ${patient.appUserId}
            or actor_user_id = ${caregiver.appUserId}
          )
          and action in (
            'care_invitation.phone_created',
            'care_invitation.accepted',
            'care_invitation.revoked',
            'care_relationship.created'
          )
      `;
      assert(
        audits.some((row) => row.action === "care_invitation.phone_created"),
      );
      assert(audits.some((row) => row.action === "care_invitation.accepted"));
      assert(audits.some((row) => row.action === "care_invitation.revoked"));
      assert(audits.some((row) => row.action === "care_relationship.created"));
      for (const row of audits) {
        assertEquals(row.metadata_json, null);
      }
    } finally {
      await admin.end({ timeout: 5 });
    }
  },
});

function auth(subject: string, email: string, phone: string): AuthUser {
  return {
    id: subject,
    email,
    phone,
    userMetadata: {},
  };
}

async function bootstrap(
  db: ReturnType<typeof createLifeMateDatabase>,
  authUser: AuthUser,
  displayName: string,
): Promise<AppIdentity> {
  await db.bootstrapUser(authUser, {
    displayName,
    locale: "fa",
    timeZone: "Asia/Tehran",
  });
  return await db.requireIdentity(authUser);
}

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  try {
    await action();
    throw new Error(`Expected ${code}.`);
  } catch (error) {
    if (!(error instanceof ApiError)) throw error;
    assertEquals(error.status, status);
    assertEquals(error.code, code);
  }
}
