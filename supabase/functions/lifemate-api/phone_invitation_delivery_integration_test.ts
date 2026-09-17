import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for phone invitation integration tests.",
  );
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name:
    "canonical phone invitation persists only hashed and masked delivery state",
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
          `phone-invite-patient-${suffix}`,
          `phone-invite-patient-${suffix}@example.test`,
          "+989121111111",
        ),
        "بیمار تست",
      );

      const invitation = await db.createInvitation(patient, {
        contactType: "phone",
        contact: "۰۹۳۵ ۱۲۳ ۵۶۷۸",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      assertEquals(invitation.contactType, "phone");
      assert(typeof invitation.token === "string" && invitation.token.length > 20);

      const invitations = await admin`
        select contact_type,contact_hash,contact_hint,token_hash,status,
               to_jsonb(i)::text as serialized
        from lifemate.care_invitations i
        where inviter_user_id = ${patient.appUserId}
          and contact_type = 'Phone'
      `;
      assertEquals(invitations.length, 1);
      const row = invitations[0];
      assertEquals(row.contact_type, "Phone");
      assertEquals(row.status, "Pending");
      assert(typeof row.contact_hash === "string" && row.contact_hash.length > 20);
      assert(typeof row.token_hash === "string" && row.token_hash.length > 20);
      assert(typeof row.contact_hint === "string" && row.contact_hint.length > 0);
      const serialized = String(row.serialized ?? "");
      assertEquals(serialized.includes("+989351234567"), false);
      assertEquals(serialized.includes("093512345678"), false);
      assertEquals(serialized.includes(String(invitation.token)), false);

      const audits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}
          and action = 'care_invitation.phone_created'
      `;
      assertEquals(Number(audits[0]?.count ?? 0), 1);
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