import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for identity bridge tests.");
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name:
    "legacy profile health ownership and care grants follow Account-to-Self-Person mapping",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const patientUserId = crypto.randomUUID();
    const caregiverUserId = crypto.randomUUID();
    const patientAccountId = crypto.randomUUID();
    const caregiverAccountId = crypto.randomUUID();
    const patientPersonId = crypto.randomUUID();
    const caregiverPersonId = crypto.randomUUID();
    const relationshipId = crypto.randomUUID();
    const medicationId = crypto.randomUUID();

    try {
      await sql`
        insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
        values
          (${patientUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()),
          (${caregiverUserId}::uuid,${crypto.randomUUID()},'Active',now(),now())
      `;

      // Remove the bootstrap same-ID compatibility projection so every tested
      // trigger must use the explicit provider-agnostic bridge below.
      await sql`
        delete from commerce.entitlements
        where grantee_account_id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
           or beneficiary_person_id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
      `;
      await sql`
        delete from ecosystem.app_enrollments
        where account_id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
      `;
      await sql`
        delete from identity.external_identities
        where account_id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
      `;
      await sql`
        delete from core.account_person_links
        where account_id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
      `;
      await sql`
        delete from identity.accounts
        where id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
      `;
      await sql`
        delete from core.persons
        where id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
      `;

      await sql`
        insert into identity.accounts(id,legacy_app_user_id,status)
        values
          (${patientAccountId}::uuid,${patientUserId}::uuid,'Active'),
          (${caregiverAccountId}::uuid,${caregiverUserId}::uuid,'Active')
      `;
      await sql`
        insert into core.persons(id,status,subject_category)
        values
          (${patientPersonId}::uuid,'Active','Adult'),
          (${caregiverPersonId}::uuid,'Active','Adult')
      `;
      await sql`
        insert into core.account_person_links(account_id,person_id,link_type,status)
        values
          (${patientAccountId}::uuid,${patientPersonId}::uuid,'Self','Active'),
          (${caregiverAccountId}::uuid,${caregiverPersonId}::uuid,'Self','Active')
      `;

      await sql`
        insert into lifemate.user_profiles(
          id,user_id,display_name,locale,time_zone,avatar_key,created_at_utc,updated_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${patientUserId}::uuid,'Mapped Patient',
          'fa','Asia/Tehran','',now(),now()
        )
      `;

      // owner_person_id is intentionally omitted; BEFORE INSERT compatibility
      // logic must resolve it through Account -> Self Person.
      await sql`
        insert into lifemate.medications(
          id,owner_user_id,name,version,created_at_utc,updated_at_utc
        ) values (
          ${medicationId}::uuid,${patientUserId}::uuid,'Mapped medication',1,now(),now()
        )
      `;

      await sql`
        insert into lifemate.care_relationships(
          id,patient_user_id,caregiver_user_id,status,
          patient_consent_version,patient_consented_at_utc,
          caregiver_consent_version,caregiver_consented_at_utc,
          created_at_utc,updated_at_utc
        ) values (
          ${relationshipId}::uuid,${patientUserId}::uuid,${caregiverUserId}::uuid,
          'Active','patient-v1',now(),'caregiver-v1',now(),now(),now()
        )
      `;

      const proof = await sql`
        select
          identity.account_id_for_legacy_app_user(${patientUserId}::uuid) as patient_account,
          core.self_person_id_for_legacy_app_user(${patientUserId}::uuid) as patient_person,
          (select person_id from core.person_profiles
            where display_name='Mapped Patient' limit 1) as profile_person,
          (select owner_person_id from lifemate.medications
            where id=${medicationId}::uuid) as medication_person,
          (select subject_person_id from security.access_grants
            where context_type='care_relationship'
              and context_id=${relationshipId}::uuid limit 1) as grant_person,
          (select grantee_account_id from security.access_grants
            where context_type='care_relationship'
              and context_id=${relationshipId}::uuid limit 1) as grant_account
      `;

      assertEquals(String(proof[0].patient_account), patientAccountId);
      assertEquals(String(proof[0].patient_person), patientPersonId);
      assertEquals(String(proof[0].profile_person), patientPersonId);
      assertEquals(String(proof[0].medication_person), patientPersonId);
      assertEquals(String(proof[0].grant_person), patientPersonId);
      assertEquals(String(proof[0].grant_account), caregiverAccountId);
    } finally {
      await sql`
        delete from lifemate.care_relationships where id=${relationshipId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from security.access_grants
        where context_type='care_relationship' and context_id=${relationshipId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from lifemate.medications where id=${medicationId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from lifemate.user_profiles
        where user_id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.person_profiles
        where person_id in (${patientPersonId}::uuid,${caregiverPersonId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from commerce.entitlements
        where grantee_account_id in (${patientAccountId}::uuid,${caregiverAccountId}::uuid)
           or beneficiary_person_id in (${patientPersonId}::uuid,${caregiverPersonId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from ecosystem.app_enrollments
        where account_id in (${patientAccountId}::uuid,${caregiverAccountId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.external_identities
        where account_id in (${patientAccountId}::uuid,${caregiverAccountId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.account_person_links
        where account_id in (${patientAccountId}::uuid,${caregiverAccountId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (${patientAccountId}::uuid,${caregiverAccountId}::uuid,
                     ${patientUserId}::uuid,${caregiverUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.persons
        where id in (${patientPersonId}::uuid,${caregiverPersonId}::uuid,
                     ${patientUserId}::uuid,${caregiverUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.app_users
        where id in (${patientUserId}::uuid,${caregiverUserId}::uuid)
      `.catch(() => undefined);
    }
  },
});
