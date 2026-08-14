import {
  assert,
  assertEquals,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createDataExportStore } from "./data_export.ts";
import {
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for data export integration tests.");
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name: "self-service export includes owned data but excludes linked-user ids and invitation hashes",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const exporter = createDataExportStore(databaseUrl);
    const suffix = crypto.randomUUID();
    const patientAuth = auth(
      `export-patient-${suffix}`,
      `export-patient-${suffix}@example.test`,
    );
    const linkedAuth = auth(
      `export-linked-${suffix}`,
      `export-linked-${suffix}@example.test`,
    );
    let patientId: string | null = null;
    let linkedId: string | null = null;

    try {
      const patient = await db.bootstrapUser(patientAuth, {
        displayName: "Export Patient",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const linked = await db.bootstrapUser(linkedAuth, {
        displayName: "Linked Person",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      patientId = String(patient.id);
      linkedId = String(linked.id);

      await db.createMedication(patientId, {
        name: `private-medication-${suffix}`,
        strengthText: "10 mg",
        form: "tablet",
        notes: "owned export note",
      });
      await db.createMedication(linkedId, {
        name: `other-person-medication-${suffix}`,
        strengthText: "20 mg",
        form: "tablet",
      });

      const relationshipId = crypto.randomUUID();
      await sql`
        insert into lifemate.care_relationships
          (id, patient_user_id, caregiver_user_id, status,
           patient_consent_version, patient_consented_at_utc,
           caregiver_consent_version, caregiver_consented_at_utc,
           created_at_utc, updated_at_utc)
        values
          (${relationshipId}, ${patientId}, ${linkedId}, 'Active',
           'care-patient-consent-v1', now(),
           'care-caregiver-consent-v1', now(), now(), now())
      `;

      const invitationContactHash = `contact-hash-must-not-export-${suffix}`;
      const invitationTokenHash = `token-hash-must-not-export-${suffix}`;
      await sql`
        insert into lifemate.care_invitations
          (id, inviter_user_id, contact_type, contact_hash, contact_hint,
           token_hash, patient_consent_version, status, expires_at_utc,
           created_at_utc)
        values
          (${crypto.randomUUID()}, ${patientId}, 'email',
           ${invitationContactHash}, 'l***@example.test',
           ${invitationTokenHash}, 'care-patient-consent-v1', 'Pending',
           now() + interval '10 minutes', now())
      `;

      const exported = await exporter.exportAccountData(patientId);
      const encoded = JSON.stringify(exported);

      assertEquals(exported.schemaVersion, "lifemate-portable-export-v1");
      assert(encoded.includes(`private-medication-${suffix}`));
      assert(encoded.includes(patientAuth.email!));
      assert(!encoded.includes(`other-person-medication-${suffix}`));
      assert(!encoded.includes(linkedAuth.email!));
      assert(!encoded.includes(linkedId));
      assert(!encoded.includes(invitationContactHash));
      assert(!encoded.includes(invitationTokenHash));

      const careAndConsent = exported.careAndConsent as Record<string, unknown>;
      const relationships = careAndConsent.relationships as Array<Record<string, unknown>>;
      assertEquals(relationships.length, 1);
      assertEquals(relationships[0].selfRole, "patient");
      assert(!("caregiverUserId" in relationships[0]));
      assert(!("patientUserId" in relationships[0]));
    } finally {
      if (patientId || linkedId) {
        const ids = [patientId, linkedId].filter((value): value is string => value != null);
        await sql`
          delete from lifemate.care_invitations
          where inviter_user_id in ${sql(ids)}
        `.catch(() => undefined);
        await sql`
          delete from lifemate.care_relationships
          where patient_user_id in ${sql(ids)} or caregiver_user_id in ${sql(ids)}
        `.catch(() => undefined);
        await sql`
          delete from lifemate.medications
          where owner_user_id in ${sql(ids)}
        `.catch(() => undefined);
        await sql`
          delete from lifemate.audit_logs
          where actor_user_id in ${sql(ids)}
        `.catch(() => undefined);
        await sql`
          delete from lifemate.user_profiles
          where user_id in ${sql(ids)}
        `.catch(() => undefined);
        await sql`
          delete from lifemate.app_users
          where id in ${sql(ids)}
        `.catch(() => undefined);
      }
      await sql.end({ timeout: 2 });
    }
  },
});

function auth(id: string, email: string): AuthUser {
  return {
    id,
    email,
    phone: null,
    userMetadata: {},
  };
}
