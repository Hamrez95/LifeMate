import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
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

      const patientCanonical = await remapSelfIdentity(
        admin,
        patient.appUserId,
      );
      const caregiverCanonical = await remapSelfIdentity(
        admin,
        caregiver.appUserId,
      );
      for (
        const [appUserId, accountId, personId] of [
          [
            patient.appUserId,
            patientCanonical.accountId,
            patientCanonical.personId,
          ],
          [
            caregiver.appUserId,
            caregiverCanonical.accountId,
            caregiverCanonical.personId,
          ],
        ]
      ) {
        assertNotEquals(appUserId, accountId);
        assertNotEquals(appUserId, personId);
        assertNotEquals(accountId, personId);
      }

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

      const persisted = await admin`
        select patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${String(relationship.id)}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].patient_person_id, patientCanonical.personId);
      assertEquals(
        persisted[0].caregiver_person_id,
        caregiverCanonical.personId,
      );

      const replayed = await db.acceptInvitation(caregiver, {
        token: second.token,
        consentVersion: "care-caregiver-consent-v1",
        confirmConsent: true,
      });
      assertEquals(replayed.id, relationship.id);

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
      const expiredId = String(expired.id);
      await admin`
        update lifemate.care_invitations
        set expires_at_utc = now() - interval '1 minute'
        where id = ${expiredId}
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

async function remapSelfIdentity(
  admin: ReturnType<typeof postgres>,
  appUserId: string,
): Promise<{ accountId: string; personId: string }> {
  const accountId = crypto.randomUUID();
  const personId = crypto.randomUUID();
  await admin.begin(async (tx) => {
    await tx`
      update identity.accounts
      set legacy_app_user_id=null,updated_at_utc=now()
      where legacy_app_user_id=${appUserId}::uuid
    `;
    await tx`
      insert into identity.accounts(id,legacy_app_user_id,status)
      values (${accountId}::uuid,${appUserId}::uuid,'Active')
    `;
    await tx`
      insert into core.persons(id,status,subject_category)
      values (${personId}::uuid,'Active','Adult')
    `;
    await tx`
      insert into core.account_person_links(account_id,person_id,link_type,status)
      values (${accountId}::uuid,${personId}::uuid,'Self','Active')
    `;
  });
  return { accountId, personId };
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
