import {
  assertEquals,
  assertNotEquals,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createDataExportStore } from "./data_export.ts";

type IdentityFixture = {
  appUserId: string;
  accountId: string;
  personId: string;
};

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for care relationship export tests.",
  );
}

const fixtureSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

async function createUnequalIdentity(): Promise<IdentityFixture> {
  const appUserId = crypto.randomUUID();
  const accountId = crypto.randomUUID();
  const personId = crypto.randomUUID();
  assertNotEquals(appUserId, accountId);
  assertNotEquals(appUserId, personId);
  assertNotEquals(accountId, personId);

  await fixtureSql`
    insert into lifemate.app_users(
      id,auth_subject,status,created_at_utc,updated_at_utc
    ) values (
      ${appUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()
    )
  `;
  await fixtureSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${appUserId}::uuid
  `;
  await fixtureSql`
    insert into identity.accounts(id,legacy_app_user_id,status)
    values (${accountId}::uuid,${appUserId}::uuid,'Active')
  `;
  await fixtureSql`
    insert into core.persons(id,status,subject_category)
    values (${personId}::uuid,'Active','Adult')
  `;
  await fixtureSql`
    insert into core.account_person_links(account_id,person_id,link_type,status)
    values (${accountId}::uuid,${personId}::uuid,'Self','Active')
  `;

  return { appUserId, accountId, personId };
}

async function cleanupIdentity(identity: IdentityFixture): Promise<void> {
  await fixtureSql`
    delete from core.account_person_links
    where account_id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
       or person_id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    delete from identity.accounts
    where id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    delete from lifemate.app_users where id=${identity.appUserId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    delete from core.persons
    where id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
  `.catch(() => undefined);
}

Deno.test({
  name:
    "care relationship export uses canonical Person membership without linked identity leakage",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const patient = await createUnequalIdentity();
    const caregiver = await createUnequalIdentity();
    const relationshipId = crypto.randomUUID();
    const exporter = createDataExportStore(databaseUrl);

    try {
      await fixtureSql`
        insert into lifemate.care_relationships(
          id,patient_user_id,caregiver_user_id,status,
          patient_consent_version,patient_consented_at_utc,
          caregiver_consent_version,caregiver_consented_at_utc,
          can_view_women_calendar,can_manage_health_record,
          created_at_utc,updated_at_utc
        ) values (
          ${relationshipId}::uuid,${patient.appUserId}::uuid,
          ${caregiver.appUserId}::uuid,'Active','patient-consent-v1',now(),
          'caregiver-consent-v1',now(),true,false,now(),now()
        )
      `;

      const canonical = await fixtureSql`
        select patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${relationshipId}::uuid
      `;
      assertEquals(canonical.length, 1);
      assertEquals(canonical[0].patient_person_id, patient.personId);
      assertEquals(canonical[0].caregiver_person_id, caregiver.personId);

      const patientExport = await exporter.exportAccountData(patient.appUserId);
      const patientCare = patientExport.careAndConsent as Record<
        string,
        unknown
      >;
      const patientRelationships = patientCare.relationships as Array<
        Record<string, unknown>
      >;
      assertEquals(patientRelationships.length, 1);
      assertEquals(patientRelationships[0].id, relationshipId);
      assertEquals(patientRelationships[0].selfRole, "patient");
      const patientEncoded = JSON.stringify(patientExport);
      assertEquals(patientEncoded.includes(caregiver.appUserId), false);
      assertEquals(patientEncoded.includes(caregiver.accountId), false);
      assertEquals(patientEncoded.includes(caregiver.personId), false);

      const caregiverExport = await exporter.exportAccountData(
        caregiver.appUserId,
      );
      const caregiverCare = caregiverExport.careAndConsent as Record<
        string,
        unknown
      >;
      const caregiverRelationships = caregiverCare.relationships as Array<
        Record<string, unknown>
      >;
      assertEquals(caregiverRelationships.length, 1);
      assertEquals(caregiverRelationships[0].id, relationshipId);
      assertEquals(caregiverRelationships[0].selfRole, "caregiver");
      const caregiverEncoded = JSON.stringify(caregiverExport);
      assertEquals(caregiverEncoded.includes(patient.appUserId), false);
      assertEquals(caregiverEncoded.includes(patient.accountId), false);
      assertEquals(caregiverEncoded.includes(patient.personId), false);

      for (const row of [patientRelationships[0], caregiverRelationships[0]]) {
        assertEquals("patientUserId" in row, false);
        assertEquals("caregiverUserId" in row, false);
        assertEquals("patientPersonId" in row, false);
        assertEquals("caregiverPersonId" in row, false);
      }
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await fixtureSql`
        delete from lifemate.care_relationships where id=${relationshipId}::uuid
      `.catch(() => undefined);
      await cleanupIdentity(patient);
      await cleanupIdentity(caregiver);
      await fixtureSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
