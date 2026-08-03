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
  throw new Error("TEST_DATABASE_URL is required for QR integration tests.");
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name: "QR invitation is consented short-lived one-time and self-safe",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const suffix = crypto.randomUUID();
    try {
      const patient = await bootstrap(
        db,
        auth(`qr-patient-${suffix}`, `qr-patient-${suffix}@example.test`),
        "بیمار QR",
      );
      const caregiver = await bootstrap(
        db,
        auth(`qr-caregiver-${suffix}`, `qr-caregiver-${suffix}@example.test`),
        "مراقب QR",
      );
      const secondCaregiver = await bootstrap(
        db,
        auth(`qr-second-${suffix}`, `qr-second-${suffix}@example.test`),
        "مراقب دوم",
      );

      await assertApiError(
        () =>
          db.createQrInvitation(patient, {
            consentVersion: "wrong",
            confirmConsent: true,
          }),
        400,
        "patient_consent_required",
      );

      const first = await db.createQrInvitation(patient, {
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      assertEquals(first.contactType, "qr");
      assert(typeof first.token === "string");

      await assertApiError(
        () =>
          db.acceptInvitation(patient, {
            token: first.token,
            consentVersion: "care-caregiver-consent-v1",
            confirmConsent: true,
          }),
        400,
        "self_invitation_not_allowed",
      );

      const second = await db.createQrInvitation(patient, {
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      assert(first.token !== second.token);

      await assertApiError(
        () =>
          db.acceptInvitation(caregiver, {
            token: first.token,
            consentVersion: "care-caregiver-consent-v1",
            confirmConsent: true,
          }),
        409,
        "invitation_not_pending",
      );

      const relationship = await db.acceptInvitation(caregiver, {
        token: second.token,
        consentVersion: "care-caregiver-consent-v1",
        confirmConsent: true,
      });
      assertEquals(relationship.status, "active");
      assertEquals(relationship.patientUserId, patient.appUserId);
      assertEquals(relationship.caregiverUserId, caregiver.appUserId);

      await assertApiError(
        () =>
          db.acceptInvitation(secondCaregiver, {
            token: second.token,
            consentVersion: "care-caregiver-consent-v1",
            confirmConsent: true,
          }),
        409,
        "invitation_not_pending",
      );

      const expired = await db.createQrInvitation(patient, {
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      await admin`
        update lifemate.care_invitations
        set expires_at_utc = now() - interval '1 minute'
        where id = ${expired.id}
      `;
      await assertApiError(
        () =>
          db.acceptInvitation(secondCaregiver, {
            token: expired.token,
            consentVersion: "care-caregiver-consent-v1",
            confirmConsent: true,
          }),
        410,
        "invitation_expired",
      );

      const audits = await admin`
        select action
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}
          and action = 'care_invitation.qr_created'
      `;
      assert(audits.length >= 3);
    } finally {
      await admin.end({ timeout: 5 });
    }
  },
});

function auth(subject: string, email: string): AuthUser {
  return {
    id: subject,
    email,
    phone: null,
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
