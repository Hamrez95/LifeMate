import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPersonTreatmentCreateStore } from "./person_treatment_create.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for atomic treatment create tests.",
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
    "atomic treatment create persists default hourly recurrence and reuses canonical medication",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const store = createPersonTreatmentCreateStore(databaseUrl);
    const planIds: string[] = [];
    const medicationIds: string[] = [];

    assertNotEquals(appUserId, accountId);
    assertNotEquals(appUserId, personId);
    assertNotEquals(accountId, personId);

    try {
      await replaceBootstrapIdentity(
        appUserId,
        accountId,
        personId,
        authSubject,
      );

      const first = await store.createTreatment(appUserId, {
        medication: {
          name: "Atomic hourly fixture",
          strengthText: "10 mg",
          form: "tablet",
          notes: "synthetic fixture",
        },
        doseText: "one tablet",
        instructions: "synthetic instruction",
        startDate: "2030-01-07",
        endDate: "2030-01-09",
        timeZone: "Asia/Tehran",
        schedules: [],
        recurrence: {
          version: 2,
          enabled: true,
          unit: "hour",
          interval: 8,
          endDate: "2030-01-09T23:59:59",
        },
        recurrenceStartLocalTime: "09:15",
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 45,
      });
      const firstPlanId = String(first.id);
      const firstMedication = first.medication as Record<string, unknown>;
      const firstMedicationId = String(firstMedication.id);
      planIds.push(firstPlanId);
      medicationIds.push(firstMedicationId);

      const persisted = await fixtureSql`
        select patient_user_id::text, patient_person_id::text,
               medication_id::text, recurrence_rule, recurrence_start_local_time::text
        from lifemate.treatment_plans
        where id=${firstPlanId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].patient_user_id, null);
      assertEquals(persisted[0].patient_person_id, personId);
      assertEquals(persisted[0].medication_id, firstMedicationId);
      assertEquals(persisted[0].recurrence_rule.enabled, true);
      assertEquals(persisted[0].recurrence_rule.unit, "hour");
      assertEquals(Number(persisted[0].recurrence_rule.interval), 8);
      assertEquals(
        String(persisted[0].recurrence_start_local_time).slice(0, 5),
        "09:15",
      );

      const schedules = await fixtureSql`
        select day_of_week, local_time::text
        from lifemate.treatment_schedules
        where treatment_plan_id=${firstPlanId}::uuid
      `;
      assertEquals(schedules.length, 1);
      assertEquals(schedules[0].day_of_week, "recurrence");
      assertEquals(String(schedules[0].local_time).slice(0, 5), "09:15");

      const second = await store.createTreatment(appUserId, {
        medication: {
          name: "  ATOMIC HOURLY FIXTURE  ",
          strengthText: "10 MG",
          form: "TABLET",
          notes: "different treatment notes",
        },
        doseText: "half tablet",
        instructions: "another legitimate plan",
        startDate: "2030-01-10",
        endDate: "2030-01-10",
        timeZone: "Asia/Tehran",
        schedules: [{ dayOfWeek: "thursday", localTime: "10:00" }],
        recurrence: { version: 2, enabled: false },
        recurrenceStartLocalTime: null,
      });
      planIds.push(String(second.id));
      const secondMedication = second.medication as Record<string, unknown>;
      assertEquals(String(secondMedication.id), firstMedicationId);

      const medicationCount = await fixtureSql`
        select count(*)::integer as count
        from lifemate.medications
        where owner_person_id=${personId}::uuid
      `;
      assertEquals(medicationCount[0].count, 1);

      const medicationAuditCount = await fixtureSql`
        select count(*)::integer as count
        from lifemate.audit_logs
        where resource_type='medication'
          and resource_id=${firstMedicationId}::uuid
          and action='medication.created'
      `;
      assertEquals(medicationAuditCount[0].count, 1);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      for (const planId of planIds) {
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
      for (const medicationId of medicationIds) {
        await fixtureSql`
          delete from lifemate.audit_logs
          where resource_type='medication' and resource_id=${medicationId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.medications where id=${medicationId}::uuid
        `.catch(() => undefined);
      }
      await cleanupIdentity(appUserId, accountId, personId);
    }
  },
});

Deno.test({
  name:
    "atomic treatment create rolls medication and audit back on plan failure",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const marker = `rollback-${crypto.randomUUID()}`;
    const store = createPersonTreatmentCreateStore(databaseUrl, {
      afterMedicationPersisted: () => {
        throw new Error("synthetic_plan_failure_after_medication");
      },
    });

    try {
      await replaceBootstrapIdentity(
        appUserId,
        accountId,
        personId,
        authSubject,
      );

      await assertRejects(
        () =>
          store.createTreatment(appUserId, {
            medication: {
              name: marker,
              strengthText: "5 mg",
              form: "tablet",
              notes: "must rollback",
            },
            doseText: "one tablet",
            startDate: "2030-02-01",
            endDate: "2030-02-01",
            timeZone: "Asia/Tehran",
            schedules: [{ dayOfWeek: "friday", localTime: "12:00" }],
            recurrence: { version: 2, enabled: false },
          }),
        Error,
        "synthetic_plan_failure_after_medication",
      );

      const medications = await fixtureSql`
        select id::text
        from lifemate.medications
        where owner_person_id=${personId}::uuid and name=${marker}
      `;
      assertEquals(medications.length, 0);

      const audits = await fixtureSql`
        select count(*)::integer as count
        from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid
          and action in ('medication.created','treatment_plan.created')
      `;
      assertEquals(audits[0].count, 0);

      const plans = await fixtureSql`
        select count(*)::integer as count
        from lifemate.treatment_plans
        where patient_person_id=${personId}::uuid
      `;
      assertEquals(plans[0].count, 0);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanupIdentity(appUserId, accountId, personId);
      await fixtureSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
