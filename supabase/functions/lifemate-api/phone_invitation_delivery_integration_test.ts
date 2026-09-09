import { assertEquals } from "jsr:@std/assert@1.0.14";
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
  name: "public relationship-aware phone invitation persists bounded state",
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
          `phone-public-patient-${suffix}`,
          `phone-public-patient-${suffix}@example.test`,
          "+989121111111",
        ),
        "Integration Patient",
      );

      const invitation = await db.createInvitation(patient, {
        contactType: "phone",
        contact: "+989351235678",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
        relationshipType: "family",
        displayName: "Family member",
      });

      assertEquals(invitation.contactType, "phone");
      assertEquals(invitation.contactHint, "+98 ••• •• 5678");
      assertEquals(invitation.relationshipType, "family");
      assertEquals(invitation.caregiverDisplayName, "Family member");

      const invitations = await admin`
        select contact_type, contact_hint, relationship_type,
               inviter_caregiver_display_name
        from lifemate.care_invitations
        where inviter_user_id = ${patient.appUserId}
          and id = ${String(invitation.id)}::uuid
      `;
      assertEquals(invitations.length, 1);
      assertEquals(invitations[0].contact_type, "Phone");
      assertEquals(invitations[0].contact_hint, "+98 ••• •• 5678");
      assertEquals(invitations[0].relationship_type, "family");
      assertEquals(
        invitations[0].inviter_caregiver_display_name,
        "Family member",
      );

      const audits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}
          and action = 'care_invitation.phone_created'
          and resource_id = ${String(invitation.id)}::uuid
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
