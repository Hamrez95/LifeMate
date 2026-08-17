import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createDataExportStore } from "./data_export.ts";
import { createPersonDoseOccurrenceStore } from "./person_dose_occurrences.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Person healthcare export tests.",
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
    "portable export selects medication treatment and dose datasets by canonical Person",
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
    const medications = createPersonMedicationStore(databaseUrl);
    const treatmentPlans = createPersonTreatmentPlanStore(databaseUrl);
    const doses = createPersonDoseOccurrenceStore(databaseUrl);
    const exporter = createDataExportStore(databaseUrl);
    const target = futureLocalSchedule();
    const ownerSentinel = `owner-export-${crypto.randomUUID()}`;
    const otherSentinel = `other-export-${crypto.randomUUID()}`;
    let ownerMedicationId: string | null = null;
    let ownerPlanId: string | null = null;
    let ownerOccurrenceId: string | null = null;
    let otherMedicationId: string | null = null;
    let otherPlanId: string | null = null;
    let otherOccurrenceId: string | null = null;

    assertNotEquals(ownerAppUserId, ownerAccountId);
    assertNotEquals(ownerAppUserId, ownerPersonId);
    assertNotEquals(ownerAccountId, ownerPersonId);
    assertNotEquals(otherAppUserId, otherAccountId);
    assertNotEquals(otherAppUserId, otherPersonId);
    assertNotEquals(otherAccountId, otherPersonId);

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

      const ownerMedication = await medications.createMedication(
        ownerAppUserId,
        {
          name: `${ownerSentinel}-medication`,
          strengthText: "10 mg",
          form: "tablet",
          notes: "Person export fixture",
        },
      );
      ownerMedicationId = String(ownerMedication.id);
      const otherMedication = await medications.createMedication(
        otherAppUserId,
        {
          name: `${otherSentinel}-medication`,
          strengthText: "20 mg",
          form: "tablet",
          notes: "unrelated export fixture",
        },
      );
      otherMedicationId = String(otherMedication.id);

      const ownerPlan = await treatmentPlans.createTreatmentPlan(
        ownerAppUserId,
        {
          medicationId: ownerMedicationId,
          doseText: `${ownerSentinel}-dose`,
          instructions: "after breakfast",
          startDate: target.date,
          endDate: target.date,
          timeZone: "Asia/Tehran",
          schedules: [{
            dayOfWeek: target.dayOfWeek,
            localTime: target.localTime,
          }],
        },
      );
      ownerPlanId = String(ownerPlan.id);
      const otherPlan = await treatmentPlans.createTreatmentPlan(
        otherAppUserId,
        {
          medicationId: otherMedicationId,
          doseText: `${otherSentinel}-dose`,
          instructions: null,
          startDate: target.date,
          endDate: target.date,
          timeZone: "Asia/Tehran",
          schedules: [{
            dayOfWeek: target.dayOfWeek,
            localTime: target.localTime,
          }],
        },
      );
      otherPlanId = String(otherPlan.id);

      const ownerDoses = await doses.listDoseOccurrences(
        ownerAppUserId,
        target.date,
        target.date,
      );
      assertEquals(ownerDoses.length, 1);
      ownerOccurrenceId = String(ownerDoses[0].id);
      const otherDoses = await doses.listDoseOccurrences(
        otherAppUserId,
        target.date,
        target.date,
      );
      assertEquals(otherDoses.length, 1);
      otherOccurrenceId = String(otherDoses[0].id);

      await doses.reportDose(ownerAppUserId, ownerOccurrenceId, {
        clientRequestId: crypto.randomUUID(),
        version: ownerDoses[0].version,
        status: "taken",
        occurredAtUtc: new Date().toISOString(),
      });
      await doses.reportDose(otherAppUserId, otherOccurrenceId, {
        clientRequestId: crypto.randomUUID(),
        version: otherDoses[0].version,
        status: "taken",
        occurredAtUtc: new Date().toISOString(),
      });

      // Simulate the next-stage compatibility freeze before exporting. These
      // legacy columns may be absent without changing export ownership scope.
      await fixtureSql`
        update lifemate.medications
        set owner_user_id=null
        where id=${ownerMedicationId}::uuid
      `;
      await fixtureSql`
        update lifemate.treatment_plans
        set patient_user_id=null
        where id=${ownerPlanId}::uuid
      `;
      await fixtureSql`
        update lifemate.dose_occurrences
        set patient_user_id=null
        where id=${ownerOccurrenceId}::uuid
      `;

      const exported = await exporter.exportAccountData(ownerAppUserId);
      assertEquals(exported.schemaVersion, "lifemate-portable-export-v1");
      const healthcare = exported.healthcare as Record<string, unknown>;
      const exportedMedications = healthcare.medications as Array<
        Record<string, unknown>
      >;
      const exportedPlans = healthcare.treatmentPlans as Array<
        Record<string, unknown>
      >;
      const exportedSchedules = healthcare.treatmentSchedules as Array<
        Record<string, unknown>
      >;
      const exportedDoses = healthcare.doseOccurrences as Array<
        Record<string, unknown>
      >;
      const exportedAdherence = healthcare.doseAdherenceEvents as Array<
        Record<string, unknown>
      >;

      assertEquals(exportedMedications.length, 1);
      assertEquals(exportedMedications[0].id, ownerMedicationId);
      assertEquals(exportedPlans.length, 1);
      assertEquals(exportedPlans[0].id, ownerPlanId);
      assertEquals(exportedPlans[0].medicationId, ownerMedicationId);
      assertEquals(exportedSchedules.length, 1);
      assertEquals(exportedSchedules[0].treatmentPlanId, ownerPlanId);
      assertEquals(exportedDoses.length, 1);
      assertEquals(exportedDoses[0].id, ownerOccurrenceId);
      assertEquals(exportedAdherence.length, 1);
      assertEquals(exportedAdherence[0].occurrenceId, ownerOccurrenceId);
      assertEquals(exportedAdherence[0].actorWasSelf, true);

      assert(otherMedicationId);
      assert(otherPlanId);
      assert(otherOccurrenceId);
      const encoded = JSON.stringify(exported);
      assert(encoded.includes(ownerSentinel));
      assert(!encoded.includes(otherSentinel));
      assert(!encoded.includes(otherMedicationId));
      assert(!encoded.includes(otherPlanId));
      assert(!encoded.includes(otherOccurrenceId));
      assert(!encoded.includes(ownerPersonId));
      assert(!encoded.includes(otherPersonId));

      // A privacy export must not silently fall back to raw AppUser ownership
      // if the canonical Self Person mapping disappears.
      await fixtureSql`
        delete from core.account_person_links
        where account_id=${ownerAccountId}::uuid
          and person_id=${ownerPersonId}::uuid
          and link_type='Self'
      `;
      await assertApiError(
        () => exporter.exportAccountData(ownerAppUserId),
        409,
        "identity_person_mapping_missing",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      for (const occurrenceId of [ownerOccurrenceId, otherOccurrenceId]) {
        if (!occurrenceId) continue;
        await fixtureSql`
          delete from lifemate.dose_adherence_events
          where occurrence_id=${occurrenceId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.dose_occurrences where id=${occurrenceId}::uuid
        `.catch(() => undefined);
      }
      for (const planId of [ownerPlanId, otherPlanId]) {
        if (!planId) continue;
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
      for (const medicationId of [ownerMedicationId, otherMedicationId]) {
        if (!medicationId) continue;
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
