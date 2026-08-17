import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Care Relationship Person identity tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

type IdentityFixture = {
  appUserId: string;
  accountId: string;
  personId: string;
};

async function createUnequalIdentity(): Promise<IdentityFixture> {
  const appUserId = crypto.randomUUID();
  const accountId = crypto.randomUUID();
  const personId = crypto.randomUUID();

  assertNotEquals(appUserId, accountId);
  assertNotEquals(appUserId, personId);
  assertNotEquals(accountId, personId);

  await sql`
    insert into lifemate.app_users(
      id,auth_subject,status,created_at_utc,updated_at_utc
    ) values (
      ${appUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()
    )
  `;

  await sql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where legacy_app_user_id=${appUserId}::uuid
  `;
  await sql`
    insert into identity.accounts(id,legacy_app_user_id,status)
    values (${accountId}::uuid,${appUserId}::uuid,'Active')
  `;
  await sql`
    insert into core.persons(id,status,subject_category)
    values (${personId}::uuid,'Active','Adult')
  `;
  await sql`
    insert into core.account_person_links(account_id,person_id,link_type,status)
    values (${accountId}::uuid,${personId}::uuid,'Self','Active')
  `;

  return { appUserId, accountId, personId };
}

async function insertActiveRelationship(
  id: string,
  patientUserId: string,
  caregiverUserId: string,
  patientPersonId?: string,
  caregiverPersonId?: string,
): Promise<void> {
  await sql`
    insert into lifemate.care_relationships(
      id,patient_user_id,caregiver_user_id,status,
      patient_consent_version,patient_consented_at_utc,
      caregiver_consent_version,caregiver_consented_at_utc,
      can_view_women_calendar,can_manage_health_record,
      patient_person_id,caregiver_person_id,
      created_at_utc,updated_at_utc
    ) values (
      ${id}::uuid,${patientUserId}::uuid,${caregiverUserId}::uuid,'Active',
      'care-patient-consent-v1',now(),
      'care-caregiver-consent-v1',now(),
      false,false,
      ${patientPersonId ?? null}::uuid,${caregiverPersonId ?? null}::uuid,
      now(),now()
    )
  `;
}

Deno.test({
  name:
    "Care Relationship dual-writes canonical Persons and rejects ambiguous identity mutation",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const patient = await createUnequalIdentity();
    const caregiver = await createUnequalIdentity();
    const relationshipId = crypto.randomUUID();
    const unmappedAppUserId = crypto.randomUUID();

    try {
      await insertActiveRelationship(
        relationshipId,
        patient.appUserId,
        caregiver.appUserId,
      );

      const persisted = await sql`
        select patient_user_id::text,caregiver_user_id::text,
               patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${relationshipId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].patient_user_id, patient.appUserId);
      assertEquals(persisted[0].caregiver_user_id, caregiver.appUserId);
      assertEquals(persisted[0].patient_person_id, patient.personId);
      assertEquals(persisted[0].caregiver_person_id, caregiver.personId);

      const canonicalPairIndex = await sql`
        select indexdef
        from pg_indexes
        where schemaname='lifemate'
          and tablename='care_relationships'
          and indexname='IX_care_relationships_patient_person_id_caregiver_person_id'
      `;
      assertEquals(canonicalPairIndex.length, 1);
      const indexDefinition = String(canonicalPairIndex[0].indexdef)
        .toLowerCase();
      assertEquals(indexDefinition.includes("unique index"), true);
      assertEquals(indexDefinition.includes("patient_person_id"), true);
      assertEquals(indexDefinition.includes("caregiver_person_id"), true);
      assertEquals(indexDefinition.includes("status"), true);
      assertEquals(indexDefinition.includes("active"), true);

      await assertRejects(
        () =>
          insertActiveRelationship(
            crypto.randomUUID(),
            patient.appUserId,
            caregiver.appUserId,
            caregiver.personId,
            caregiver.personId,
          ),
        Error,
        "care_relationship_patient_person_mismatch",
      );

      await assertRejects(
        () =>
          sql`
            update lifemate.care_relationships
            set caregiver_user_id=${patient.appUserId}::uuid,
                updated_at_utc=now()
            where id=${relationshipId}::uuid
          `.then(() => undefined),
        Error,
        "care_relationship_participant_immutable",
      );

      await sql`
        update lifemate.care_relationships
        set status='Revoked',
            revoked_by_user_id=${patient.appUserId}::uuid,
            revoked_at_utc=now(),
            updated_at_utc=now()
        where id=${relationshipId}::uuid
      `;
      const revoked = await sql`
        select status,patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${relationshipId}::uuid
      `;
      assertEquals(revoked[0].status, "Revoked");
      assertEquals(revoked[0].patient_person_id, patient.personId);
      assertEquals(revoked[0].caregiver_person_id, caregiver.personId);

      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values (
          ${unmappedAppUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()
        )
      `;
      await sql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where legacy_app_user_id=${unmappedAppUserId}::uuid
      `;
      await assertRejects(
        () =>
          insertActiveRelationship(
            crypto.randomUUID(),
            unmappedAppUserId,
            caregiver.appUserId,
          ),
        Error,
        "care_relationship_patient_person_missing",
      );
    } finally {
      await sql`
        delete from lifemate.care_relationships
        where id=${relationshipId}::uuid
      `.catch(() => undefined);
      await sql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
