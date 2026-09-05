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
  name: "public phone invitation uses the restored contact-bound domain flow",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const suffix = crypto.randomUUID();
    let patient: AppIdentity | null = null;
    let invitationId: string | null = null;

    try {
      patient = await bootstrap(
        db,
        auth(
          `phone-public-patient-${suffix}`,
          `phone-public-patient-${suffix}@example.test`,
          "+989121111111",
        ),
        "بیمار تست",
      );

      const invitation = await db.createInvitation(patient, {
        contactType: "phone",
        contact: "۰۹۳۵ ۱۲۳ ۵۶۷۸",
        relationshipType: "family",
        displayName: "مراقب تست",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });

      invitationId = String(invitation.id);
      assert(invitationId.length > 0);
      assertEquals(invitation.contactType, "phone");
      assertEquals(invitation.relationshipType, "family");
      assertEquals(invitation.caregiverDisplayName, "مراقب تست");
      assert(typeof invitation.token === "string" && invitation.token.length > 0);

      const invitations = await admin`
        select contact_type, status, contact_hint, contact_hash, token_hash,
               relationship_type, inviter_caregiver_display_name
        from lifemate.care_invitations
        where id = ${invitationId}::uuid
          and inviter_user_id = ${patient.appUserId}::uuid
      `;
      assertEquals(invitations.length, 1);
      assertEquals(invitations[0].contact_type, "Phone");
      assertEquals(invitations[0].status, "Pending");
      assertEquals(invitations[0].relationship_type, "family");
      assertEquals(invitations[0].inviter_caregiver_display_name, "مراقب تست");
      assert(typeof invitations[0].contact_hash === "string");
      assert(typeof invitations[0].token_hash === "string");
      assert(!JSON.stringify(invitations[0]).includes("09351235678"));
      assert(!JSON.stringify(invitations[0]).includes("+989351235678"));

      const audits = await admin`
        select metadata_json
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}::uuid
          and action = 'care_invitation.phone_created'
          and resource_id = ${invitationId}::uuid
      `;
      assertEquals(audits.length, 1);
      assertEquals(audits[0].metadata_json, null);
    } finally {
      if (invitationId) {
        await admin`
          delete from lifemate.audit_logs
          where resource_id = ${invitationId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.care_invitations
          where id = ${invitationId}::uuid
        `.catch(() => undefined);
      }
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
