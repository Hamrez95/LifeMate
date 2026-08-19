import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { runTreatmentDoseOwnerRetirement } from "../../../tools/security/treatment-dose-owner-retirement.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createDataExportStore } from "./data_export.ts";
import { createPersonDoseOccurrenceStore } from "./person_dose_occurrences.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Treatment/Dose owner retirement tests.",
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
    ) values(
      ${appUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()
    )
  `;
  await sql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${appUserId}::uuid
  `;
  await sql`
    insert into identity.accounts(id,legacy_app_user_id,status)
    values(${accountId}::uuid,${appUserId}::uuid,'Active')
  `;
  await sql`
    insert into core.persons(id,status,subject_category)
    values(${personId}::uuid,'Active','Adult')
  `;
  await sql`
    insert into core.account_person_links(account_id,person_id,link_type,status)
    values(${accountId}::uuid,${personId}::uuid,'Self','Active')
  `;
  return { appUserId, accountId, personId };
}

async function cleanupIdentity(identity: IdentityFixture): Promise<void> {
  await sql`
    delete from core.account_person_links
    where account_id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
       or person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from identity.accounts
    where id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from lifemate.app_users where id=${identity.appUserId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from core.person_profiles where person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from core.persons where id=${identity.personId}::uuid
  `.catch(() => undefined);
}

Deno.test({
  name:
    "Treatment/Dose bounded owner retirement preserves Person runtime/export and supports explicit rollback",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const owner = await createUnequalIdentity();
    const unrelated = await createUnequalIdentity();
    const medications = createPersonMedicationStore(databaseUrl);
    const treatments = createPersonTreatmentPlanStore(databaseUrl);
    const doses = createPersonDoseOccurrenceStore(databaseUrl);
    const exporter = createDataExportStore(databaseUrl);
    const schedule = futureLocalSchedule();
    let medicationId: string | null = null;
    let planId: string | null = null;
    let occurrenceId: string | null = null;

    try {
      const medication = await medications.createMedication(owner.appUserId, {
        name: `retirement-med-${crypto.randomUUID()}`,
        strengthText: "10 mg",
        form: "tablet",
        notes: "Treatment/Dose retirement fixture",
      });
      medicationId = String(medication.id);

      const plan = await treatments.createTreatmentPlan(owner.appUserId, {
        medicationId,
        doseText: "1 tablet",
        instructions: "after breakfast",
        startDate: schedule.date,
        endDate: schedule.date,
        timeZone: "Asia/Tehran",
        schedules: [{
          dayOfWeek: schedule.dayOfWeek,
          localTime: schedule.localTime,
        }],
      });
      planId = String(plan.id);

      const materialized = await doses.listDoseOccurrences(
        owner.appUserId,
        schedule.date,
        schedule.date,
      );
      assertEquals(materialized.length, 1);
      occurrenceId = String(materialized[0].id);

      // Current runtime is already Person-only. Simulate the historical rows
      // that remain in production so the retirement tool exercises real linkage.
      await sql`
        update lifemate.treatment_plans
        set patient_user_id=${owner.appUserId}::uuid
        where id=${planId}::uuid
      `;
      await sql`
        update lifemate.dose_occurrences
        set patient_user_id=${owner.appUserId}::uuid
        where id=${occurrenceId}::uuid
      `;

      const before = await sql`
        select 'treatment' as kind,id::text,patient_user_id::text,
               patient_person_id::text,updated_at_utc::text,status::text
        from lifemate.treatment_plans where id=${planId}::uuid
        union all
        select 'dose',id::text,patient_user_id::text,
               patient_person_id::text,updated_at_utc::text,status::text
        from lifemate.dose_occurrences where id=${occurrenceId}::uuid
        order by kind
      `;
      assertEquals(before.length, 2);

      const readiness = await runTreatmentDoseOwnerRetirement({
        databaseUrl,
        operation: "readiness",
        mode: "dry-run",
        maxRows: 10,
      });
      assertEquals(readiness.readiness.ready, true);
      assertEquals(readiness.readiness.treatmentPlans, 1);
      assertEquals(readiness.readiness.doseOccurrences, 1);
      assertEquals(readiness.readiness.totalRows, 2);
      assertEquals(readiness.readiness.linkedRows, 2);
      assertEquals(readiness.readiness.missingMappings, 0);
      assertEquals(readiness.readiness.ambiguousMappings, 0);
      assertEquals(readiness.readiness.mismatchedLegacyOwners, 0);
      assertEquals(readiness.readiness.dosePlanPersonMismatches, 0);

      const dryRun = await runTreatmentDoseOwnerRetirement({
        databaseUrl,
        operation: "scrub",
        mode: "dry-run",
        maxRows: 10,
      });
      assertEquals(dryRun.scannedRows, 2);
      assertEquals(dryRun.changedRows, 0);

      await assertRejects(
        () =>
          runTreatmentDoseOwnerRetirement({
            databaseUrl,
            operation: "scrub",
            mode: "apply",
            maxRows: 10,
          }),
        Error,
        "SCRUB-TREATMENT-DOSE-OWNERS",
      );

      const scrub = await runTreatmentDoseOwnerRetirement({
        databaseUrl,
        operation: "scrub",
        mode: "apply",
        maxRows: 10,
        confirmation: "SCRUB-TREATMENT-DOSE-OWNERS",
      });
      assertEquals(scrub.scannedRows, 2);
      assertEquals(scrub.changedRows, 2);
      assertEquals(scrub.hasMore, false);

      const after = await sql`
        select 'treatment' as kind,id::text,patient_user_id::text,
               patient_person_id::text,updated_at_utc::text,status::text
        from lifemate.treatment_plans where id=${planId}::uuid
        union all
        select 'dose',id::text,patient_user_id::text,
               patient_person_id::text,updated_at_utc::text,status::text
        from lifemate.dose_occurrences where id=${occurrenceId}::uuid
        order by kind
      `;
      assertEquals(after.every((row) => row.patient_user_id == null), true);
      assertEquals(
        after.every((row) => row.patient_person_id === owner.personId),
        true,
      );
      for (let index = 0; index < before.length; index += 1) {
        assertEquals(after[index].updated_at_utc, before[index].updated_at_utc);
        assertEquals(after[index].status, before[index].status);
      }

      const plansAfterScrub = await treatments.listTreatmentPlans(
        owner.appUserId,
      );
      assertEquals(plansAfterScrub.length, 1);
      assertEquals(plansAfterScrub[0].id, planId);
      const dosesAfterScrub = await doses.listDoseOccurrences(
        owner.appUserId,
        schedule.date,
        schedule.date,
      );
      assertEquals(dosesAfterScrub.length, 1);
      assertEquals(dosesAfterScrub[0].id, occurrenceId);

      const exported = await exporter.exportAccountData(owner.appUserId);
      const healthcare = exported.healthcare as Record<string, unknown>;
      const exportedPlans = healthcare.treatmentPlans as Array<
        Record<string, unknown>
      >;
      const exportedDoses = healthcare.doseOccurrences as Array<
        Record<string, unknown>
      >;
      assertEquals(exportedPlans.some((row) => row.id === planId), true);
      assertEquals(exportedDoses.some((row) => row.id === occurrenceId), true);
      const encoded = JSON.stringify(healthcare);
      assertEquals(encoded.includes(owner.personId), false);
      assertEquals(encoded.includes(owner.accountId), false);
      assertEquals(encoded.includes(owner.appUserId), false);

      const scrubAgain = await runTreatmentDoseOwnerRetirement({
        databaseUrl,
        operation: "scrub",
        mode: "apply",
        maxRows: 10,
        confirmation: "SCRUB-TREATMENT-DOSE-OWNERS",
      });
      assertEquals(scrubAgain.scannedRows, 0);
      assertEquals(scrubAgain.changedRows, 0);

      const rehydrateDryRun = await runTreatmentDoseOwnerRetirement({
        databaseUrl,
        operation: "rehydrate",
        mode: "dry-run",
        maxRows: 10,
      });
      assertEquals(rehydrateDryRun.scannedRows, 2);
      assertEquals(rehydrateDryRun.changedRows, 0);

      await assertRejects(
        () =>
          runTreatmentDoseOwnerRetirement({
            databaseUrl,
            operation: "rehydrate",
            mode: "apply",
            maxRows: 10,
          }),
        Error,
        "REHYDRATE-TREATMENT-DOSE-OWNERS",
      );

      const rehydrate = await runTreatmentDoseOwnerRetirement({
        databaseUrl,
        operation: "rehydrate",
        mode: "apply",
        maxRows: 10,
        confirmation: "REHYDRATE-TREATMENT-DOSE-OWNERS",
      });
      assertEquals(rehydrate.scannedRows, 2);
      assertEquals(rehydrate.changedRows, 2);
      assertEquals(rehydrate.hasMore, false);

      const rehydrated = await sql`
        select patient_user_id::text from lifemate.treatment_plans
        where id=${planId}::uuid
        union all
        select patient_user_id::text from lifemate.dose_occurrences
        where id=${occurrenceId}::uuid
      `;
      assertEquals(
        rehydrated.every((row) => row.patient_user_id === owner.appUserId),
        true,
      );

      // A stale/wrong compatibility identifier must never be silently scrubbed.
      await sql`
        update lifemate.treatment_plans
        set patient_user_id=${unrelated.appUserId}::uuid
        where id=${planId}::uuid
      `;
      await assertRejects(
        () =>
          runTreatmentDoseOwnerRetirement({
            databaseUrl,
            operation: "readiness",
            mode: "dry-run",
            maxRows: 10,
          }),
        Error,
        "treatment_dose_owner_retirement_mapping_mismatch",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      if (occurrenceId) {
        await sql`
          delete from lifemate.dose_adherence_events
          where occurrence_id=${occurrenceId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from lifemate.dose_occurrences where id=${occurrenceId}::uuid
        `.catch(() => undefined);
      }
      if (planId) {
        await sql`
          delete from lifemate.treatment_schedules
          where treatment_plan_id=${planId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from lifemate.audit_logs
          where resource_type='treatment_plan' and resource_id=${planId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from lifemate.treatment_plans where id=${planId}::uuid
        `.catch(() => undefined);
      }
      if (medicationId) {
        await sql`
          delete from lifemate.audit_logs
          where resource_type='medication' and resource_id=${medicationId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from lifemate.medications where id=${medicationId}::uuid
        `.catch(() => undefined);
      }
      await cleanupIdentity(owner);
      await cleanupIdentity(unrelated);
      await sql.end({ timeout: 1 }).catch(() => undefined);
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
