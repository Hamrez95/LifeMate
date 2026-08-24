import { assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Person relationship management tests.",
  );
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name:
    "relationship list permission ownership revocation and caregiver phone use canonical Person membership",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const suffix = crypto.randomUUID();
    const relationshipId = crypto.randomUUID();
    const patientPhone = "+989121234567";

    try {
      const patient = await bootstrap(
        db,
        auth(`rel-patient-${suffix}`, `rel-patient-${suffix}@example.test`),
        "Canonical Patient",
      );
      const caregiver = await bootstrap(
        db,
        auth(`rel-caregiver-${suffix}`, `rel-caregiver-${suffix}@example.test`),
        "Canonical Caregiver",
      );
      const unrelated = await bootstrap(
        db,
        auth(`rel-unrelated-${suffix}`, `rel-unrelated-${suffix}@example.test`),
        "Canonical Unrelated",
      );

      const patientCanonical = await remapSelfIdentity(
        admin,
        patient.appUserId,
        "Canonical Patient",
      );
      const caregiverCanonical = await remapSelfIdentity(
        admin,
        caregiver.appUserId,
        "Canonical Caregiver",
      );
      const unrelatedCanonical = await remapSelfIdentity(
        admin,
        unrelated.appUserId,
        "Canonical Unrelated",
      );

      for (
        const [identity, canonical] of [
          [patient, patientCanonical],
          [caregiver, caregiverCanonical],
          [unrelated, unrelatedCanonical],
        ] as const
      ) {
        assertNotEquals(identity.appUserId, canonical.accountId);
        assertNotEquals(identity.appUserId, canonical.personId);
        assertNotEquals(canonical.accountId, canonical.personId);
      }

      await admin`
        update lifemate.user_profiles
        set phone_number=${patientPhone},updated_at_utc=now()
        where user_id=${patient.appUserId}::uuid
      `;
      await admin`
        insert into lifemate.care_relationships(
          id,patient_user_id,caregiver_user_id,status,
          patient_consent_version,patient_consented_at_utc,
          caregiver_consent_version,caregiver_consented_at_utc,
          created_at_utc,updated_at_utc
        ) values (
          ${relationshipId}::uuid,${patient.appUserId}::uuid,
          ${caregiver.appUserId}::uuid,'Active',
          'care-patient-consent-v1',now(),
          'care-caregiver-consent-v1',now(),now(),now()
        )
      `;

      const patientRows = await db.listRelationships(patient.appUserId);
      assertEquals(patientRows.length, 1);
      assertEquals(patientRows[0].id, relationshipId);
      assertEquals(patientRows[0].patientUserId, patient.appUserId);
      assertEquals(patientRows[0].caregiverUserId, caregiver.appUserId);
      assertEquals(patientRows[0].patientDisplayName, "Canonical Patient");
      assertEquals(
        patientRows[0].caregiverDisplayName,
        "Canonical Caregiver",
      );
      assertEquals(patientRows[0].patientPhoneNumber, null);

      const caregiverRows = await db.listRelationships(caregiver.appUserId);
      assertEquals(caregiverRows.length, 1);
      assertEquals(caregiverRows[0].id, relationshipId);
      assertEquals(caregiverRows[0].patientPhoneNumber, patientPhone);

      const unrelatedRows = await db.listRelationships(unrelated.appUserId);
      assertEquals(unrelatedRows.length, 0);

      await assertApiError(
        () =>
          db.updateRelationshipPermissions(
            caregiver.appUserId,
            relationshipId,
            { canViewWomenCalendar: true },
          ),
        404,
        "relationship_not_found",
      );

      const updated = await db.updateRelationshipPermissions(
        patient.appUserId,
        relationshipId,
        { canViewWomenCalendar: true },
      );
      assertEquals(updated.canViewWomenCalendar, true);

      await assertApiError(
        () => db.revokeRelationship(unrelated.appUserId, relationshipId),
        404,
        "relationship_not_found",
      );

      await db.revokeRelationship(caregiver.appUserId, relationshipId);
      await db.revokeRelationship(caregiver.appUserId, relationshipId);

      const revoked = await admin`
        select status,revoked_by_user_id::text,
               patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${relationshipId}::uuid
      `;
      assertEquals(revoked.length, 1);
      assertEquals(revoked[0].status, "Revoked");
      assertEquals(revoked[0].revoked_by_user_id, caregiver.appUserId);
      assertEquals(revoked[0].patient_person_id, patientCanonical.personId);
      assertEquals(revoked[0].caregiver_person_id, caregiverCanonical.personId);

      const afterRevoke = await db.listRelationships(caregiver.appUserId);
      assertEquals(afterRevoke.length, 1);
      assertEquals(afterRevoke[0].status, "revoked");
      assertEquals(afterRevoke[0].patientPhoneNumber, null);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await admin.end({ timeout: 5 }).catch(() => undefined);
    }
  },
});

function auth(subject: string, email: string): AuthUser {
  return { id: subject, email, phone: null, userMetadata: {} };
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
  displayName: string,
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
      insert into core.person_profiles(person_id,display_name,locale,time_zone)
      values (${personId}::uuid,${displayName},'fa','Asia/Tehran')
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
  } catch (error) {
    if (!(error instanceof ApiError)) throw error;
    assertEquals(error.status, status);
    assertEquals(error.code, code);
    return;
  }
  throw new Error(`Expected ApiError ${status}/${code}.`);
}
