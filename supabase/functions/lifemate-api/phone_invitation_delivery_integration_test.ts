import { assert, assertEquals, assertMatch, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for phone invitation delivery integration tests.",
  );
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name: "public phone invitation facade delivers once and redacts raw token",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const delivered: Array<{ phoneE164: string; token: string }> = [];
    const db = createLifeMateDatabase(databaseUrl, contactSecret, {
      phoneInvitationDelivery: {
        requireEnabled() {},
        async deliver(phoneE164, token) {
          delivered.push({ phoneE164, token });
        },
      },
    });
    const suffix = crypto.randomUUID();
    try {
      const patient = await bootstrap(
        db,
        auth(
          `phone-delivery-patient-${suffix}`,
          `phone-delivery-patient-${suffix}@example.test`,
          "+989121111111",
        ),
        "بیمار ارسال",
      );
      const caregiver = await bootstrap(
        db,
        auth(
          `phone-delivery-caregiver-${suffix}`,
          `phone-delivery-caregiver-${suffix}@example.test`,
          "+989351235678",
        ),
        "مراقب ارسال",
      );

      const invitation = await db.createInvitation(patient, {
        contactType: "phone",
        contact: "۰۹۳۵ ۱۲۳ ۵۶۷۸",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });

      assertEquals(invitation.contactType, "phone");
      assertEquals(invitation.contactHint, "+98 ••• •• 5678");
      assertEquals("token" in invitation, false);
      assertEquals(delivered.length, 1);
      assertEquals(delivered[0].phoneE164, "+989351235678");
      assertMatch(delivered[0].token, /^\d{10}$/);

      const stored = await admin`
        select token_hash, contact_hash, contact_hint
        from lifemate.care_invitations
        where id = ${String(invitation.id)}
      `;
      assertEquals(stored.length, 1);
      assertEquals(stored[0].contact_hint, "+98 ••• •• 5678");
      assert(!String(stored[0].token_hash).includes(delivered[0].token));
      assert(!String(stored[0].contact_hash).includes("09351235678"));
      assert(!String(stored[0].contact_hash).includes("+989351235678"));

      const relationship = await db.acceptInvitation(caregiver, {
        token: delivered[0].token,
        consentVersion: "care-caregiver-consent-v1",
        confirmConsent: true,
      });
      assertEquals(relationship.status, "active");
      assertEquals(relationship.patientUserId, patient.appUserId);
      assertEquals(relationship.caregiverUserId, caregiver.appUserId);

      const createAudits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}
          and action = 'care_invitation.phone_created'
          and resource_id = ${String(invitation.id)}
      `;
      assertEquals(Number(createAudits[0]?.count ?? 0), 1);
    } finally {
      await admin.end({ timeout: 5 });
    }
  },
});

Deno.test({
  name: "delivery failure rolls back invitation and audit so retry does not duplicate domain state",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const suffix = crypto.randomUUID();
    const patientAuth = auth(
      `phone-rollback-patient-${suffix}`,
      `phone-rollback-patient-${suffix}@example.test`,
      "+989121111112",
    );
    const failingDb = createLifeMateDatabase(databaseUrl, contactSecret, {
      phoneInvitationDelivery: {
        requireEnabled() {},
        deliver() {
          return Promise.reject(new Error("simulated-provider-failure"));
        },
      },
    });
    try {
      const patient = await bootstrap(failingDb, patientAuth, "بیمار بازگشت");
      const body = {
        contactType: "phone",
        contact: "+989361234567",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      };

      await assertRejects(
        () => failingDb.createInvitation(patient, body),
        Error,
        "simulated-provider-failure",
      );

      const afterFailure = await admin`
        select count(*)::int as count
        from lifemate.care_invitations
        where inviter_user_id = ${patient.appUserId}
          and contact_type = 'Phone'
          and contact_hint = '+98 ••• •• 4567'
      `;
      assertEquals(Number(afterFailure[0]?.count ?? 0), 0);
      const auditAfterFailure = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}
          and action = 'care_invitation.phone_created'
      `;
      assertEquals(Number(auditAfterFailure[0]?.count ?? 0), 0);

      const delivered: string[] = [];
      const retryDb = createLifeMateDatabase(databaseUrl, contactSecret, {
        phoneInvitationDelivery: {
          requireEnabled() {},
          async deliver(_phoneE164, token) {
            delivered.push(token);
          },
        },
      });
      const retryIdentity = await retryDb.requireIdentity(patientAuth);
      const retry = await retryDb.createInvitation(retryIdentity, body);
      assertEquals(retry.contactType, "phone");
      assertEquals(delivered.length, 1);

      const afterRetry = await admin`
        select count(*)::int as count
        from lifemate.care_invitations
        where inviter_user_id = ${patient.appUserId}
          and contact_type = 'Phone'
          and contact_hint = '+98 ••• •• 4567'
          and status = 'Pending'
      `;
      assertEquals(Number(afterRetry[0]?.count ?? 0), 1);
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
