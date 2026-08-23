import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for phone invitation retirement tests.");
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name: "legacy public phone invitation fails closed without creating domain state",
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
          `phone-retired-patient-${suffix}`,
          `phone-retired-patient-${suffix}@example.test`,
          "+989121111111",
        ),
        "بیمار تست",
      );

      const error = await assertRejects(
        () => db.createInvitation(patient, {
          contactType: "phone",
          contact: "۰۹۳۵ ۱۲۳ ۵۶۷۸",
          consentVersion: "care-patient-consent-v1",
          confirmConsent: true,
        }),
        ApiError,
      );
      assertEquals(error.status, 410);
      assertEquals(error.code, "phone_care_invitation_retired");

      const invitations = await admin`
        select count(*)::int as count
        from lifemate.care_invitations
        where inviter_user_id = ${patient.appUserId}
          and contact_type = 'Phone'
      `;
      assertEquals(Number(invitations[0]?.count ?? 0), 0);

      const audits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}
          and action = 'care_invitation.phone_created'
      `;
      assertEquals(Number(audits[0]?.count ?? 0), 0);
    } finally {
      await admin.end({ timeout: 5 });
    }
  },
});

function auth(subject: string, email: string, phone: string): AuthUser {
  return { id: subject, email, phone, userMetadata: {} };
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
