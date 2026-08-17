import { assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPersonDoseOccurrenceStore } from "./person_dose_occurrences.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for person dose occurrence tests.",
  );
}

const fixtureSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

async function replaceBootstrapIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
  authSubject: string,
): Promise<void> {
  await fixtureSql`
    insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
    values (${appUserId}::uuid,${authSubject},'Active',now(),now())
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
}

async function cleanupIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
): Promise<void> {
  await fixtureSql`
    delete from core.account_person_links
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
       or person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    delete from identity.accounts
    where id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    delete from lifemate.app_users where id=${appUserId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    delete from core.persons
    where id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
}

Deno.test({
  name:
    "dose occurrence runtime materializes and authorizes by canonical Person",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const ownerAppUserId = crypto.randomUUID();
    const ownerAccountId = crypto.randomUUID();
    const ownerPersonId = crypto.randomUUID();
    const ownerAuthSubject = crypto.randomUUID();
    const otherAppUserId = crypto.randomUUID();
    const otherAccountId = crypto.randomUUID();
    const otherPersonId = crypto.randomUUID();
    const otherAuthSubject = crypto.randomUUID();
    const caregiverAppUserId = crypto.randomUUID();
    const caregiverAccountId = crypto.randomUUID();
    const caregiverPersonId = crypto.randomUUID();
    const caregiverAuthSubject = crypto.randomUUID();
    const relationshipId = crypto.randomUUID();
    const medications = createPersonMedicationStore(databaseUrl);
    const treatmentPlans = createPersonTreatmentPlanStore(databaseUrl);
    const doses = createPersonDoseOccurrenceStore(databaseUrl);
    const target = futureLocalSchedule();
    let medicationId: string | null = null;
    let planId: string | null = null;
    let occurrenceId: string | null = null;

    for (
      const [appUserId, accountId, personId] of [
        [ownerAppUserId, ownerAccountId, ownerPersonId],
        [otherAppUserId, otherAccountId, otherPersonId],
        [caregiverAppUserId, caregiverAccountId, caregiverPersonId],
      ]
    ) {
      assertNotEquals(appUserId, accountId);
      assertNotEquals(appUserId, personId);
      assertNotEquals(accountId, personId);
    }

    try {
      await replaceBootstrapIdentity(
        ownerAppUserId,
        ownerAccountId,
        ownerPersonId,
        ownerAuthSubject,
      );
      await replaceBootstrapIdentity(
        otherAppUserId,
        otherAccountId,
        otherPersonId,
        otherAuthSubject,
      );
      await replaceBootstrapIdentity(
        caregiverAppUserId,
        caregiverAccountId,
        caregiverPersonId,
        caregiverAuthSubject,
      );

      const medication = await medications.createMedication(ownerAppUserId, {
        name: "Person-owned dose fixture",
        strengthText: "10 mg",
        form: "tablet",
        notes: "synthetic integration fixture",
      });
      medicationId = String(medication.id);

      const plan = await treatmentPlans.createTreatmentPlan(ownerAppUserId, {
        medicationId,
        doseText: "one tablet",
        instructions: null,
        startDate: target.date,
        endDate: target.date,
        timeZone: "Asia/Tehran",
        schedules: [{
          dayOfWeek: target.dayOfWeek,
          localTime: target.localTime,
        }],
      });
      planId = String(plan.id);

      const ownerRows = await doses.listDoseOccurrences(
        ownerAppUserId,
        target.date,
        target.date,
      );
      assertEquals(ownerRows.length, 1);
      occurrenceId = String(ownerRows[0].id);

      const persisted = await fixtureSql`
        select patient_user_id::text,patient_person_id::text
        from lifemate.dose_occurrences
        where id=${occurrenceId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].patient_user_id, ownerAppUserId);
      assertEquals(persisted[0].patient_person_id, ownerPersonId);

      const unrelatedRows = await doses.listDoseOccurrences(
        otherAppUserId,
        target.date,
        target.date,
      );
      assertEquals(unrelatedRows.length, 0);

      await assertApiError(
        () =>
          doses.reportDose(otherAppUserId, occurrenceId, {
            clientRequestId: crypto.randomUUID(),
            version: ownerRows[0].version,
            status: "taken",
            occurredAtUtc: new Date().toISOString(),
          }),
        404,
        "dose_occurrence_not_found",
      );

      await fixtureSql`
        insert into lifemate.care_relationships
          (id,patient_user_id,caregiver_user_id,status,
           patient_consent_version,patient_consented_at_utc,
           caregiver_consent_version,caregiver_consented_at_utc,
           created_at_utc,updated_at_utc)
        values
          (${relationshipId}::uuid,${ownerAppUserId}::uuid,
           ${caregiverAppUserId}::uuid,'Active','test-patient-consent',now(),
           'test-caregiver-consent',now(),now(),now())
      `;

      const caregiverBeforeFreeze = await doses.listCareDoseOccurrences(
        caregiverAppUserId,
        ownerAppUserId,
        target.date,
        target.date,
      );
      assertEquals(caregiverBeforeFreeze.length, 1);
      assertEquals(caregiverBeforeFreeze[0].id, occurrenceId);

      // Simulate the eventual legacy compatibility freeze. Re-materialization
      // must hit the existing schedule/time row, and all ownership filtering
      // must remain Person-based for both patient and caregiver paths.
      await fixtureSql`
        update lifemate.dose_occurrences
        set patient_user_id=null
        where id=${occurrenceId}::uuid
      `;

      const ownerAfterFreeze = await doses.listDoseOccurrences(
        ownerAppUserId,
        target.date,
        target.date,
      );
      assertEquals(ownerAfterFreeze.length, 1);
      assertEquals(ownerAfterFreeze[0].id, occurrenceId);

      const caregiverAfterFreeze = await doses.listCareDoseOccurrences(
        caregiverAppUserId,
        ownerAppUserId,
        target.date,
        target.date,
      );
      assertEquals(caregiverAfterFreeze.length, 1);
      assertEquals(caregiverAfterFreeze[0].id, occurrenceId);

      const reported = await doses.reportDose(ownerAppUserId, occurrenceId, {
        clientRequestId: crypto.randomUUID(),
        version: ownerAfterFreeze[0].version,
        status: "taken",
        occurredAtUtc: new Date().toISOString(),
      });
      assertEquals(reported.status, "taken");

      const ownershipAfterReport = await fixtureSql`
        select patient_user_id::text,patient_person_id::text
        from lifemate.dose_occurrences
        where id=${occurrenceId}::uuid
      `;
      assertEquals(ownershipAfterReport[0].patient_user_id, null);
      assertEquals(ownershipAfterReport[0].patient_person_id, ownerPersonId);

      const adherenceRows = await fixtureSql`
        select actor_user_id::text
        from lifemate.dose_adherence_events
        where occurrence_id=${occurrenceId}::uuid
      `;
      assertEquals(adherenceRows.length, 1);
      assertEquals(adherenceRows[0].actor_user_id, ownerAppUserId);
      assertNotEquals(adherenceRows[0].actor_user_id, ownerPersonId);

      await assertApiError(
        () =>
          doses.listDoseOccurrences(
            crypto.randomUUID(),
            target.date,
            target.date,
          ),
        409,
        "identity_person_mapping_missing",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      if (occurrenceId) {
        await fixtureSql`
          delete from lifemate.dose_adherence_events
          where occurrence_id=${occurrenceId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.dose_occurrences where id=${occurrenceId}::uuid
        `.catch(() => undefined);
      }
      await fixtureSql`
        delete from lifemate.care_relationships where id=${relationshipId}::uuid
      `.catch(() => undefined);
      if (planId) {
        await fixtureSql`
          delete from lifemate.treatment_schedules
          where treatment_plan_id=${planId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.audit_logs
          where resource_type='treatment_plan' and resource_id=${planId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.treatment_plans where id=${planId}::uuid
        `.catch(() => undefined);
      }
      if (medicationId) {
        await fixtureSql`
          delete from lifemate.audit_logs
          where resource_type='medication' and resource_id=${medicationId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.medications where id=${medicationId}::uuid
        `.catch(() => undefined);
      }
      await cleanupIdentity(ownerAppUserId, ownerAccountId, ownerPersonId);
      await cleanupIdentity(otherAppUserId, otherAccountId, otherPersonId);
      await cleanupIdentity(
        caregiverAppUserId,
        caregiverAccountId,
        caregiverPersonId,
      );
      await fixtureSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

function futureLocalSchedule(): {
  date: string;
  dayOfWeek: string;
  localTime: string;
} {
  const future = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "long",
  });
  const parts = Object.fromEntries(
    formatter.formatToParts(future).map((part) => [part.type, part.value]),
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    dayOfWeek: parts.weekday,
    localTime: "09:00",
  };
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
