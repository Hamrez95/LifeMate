import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for person treatment plan tests.",
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
  name: "treatment plan runtime writes and authorizes canonical Person only",
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
    let medicationId: string | null = null;
    let planId: string | null = null;

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

      const medication = await medications.createMedication(ownerAppUserId, {
        name: "Person-owned treatment fixture",
        strengthText: "10 mg",
        form: "tablet",
        notes: "synthetic integration fixture",
      });
      medicationId = String(medication.id);

      await assertApiError(
        () =>
          treatmentPlans.createTreatmentPlan(otherAppUserId, {
            medicationId,
            doseText: "one tablet",
            instructions: null,
            startDate: "2030-01-07",
            endDate: "2030-01-07",
            timeZone: "Asia/Tehran",
            schedules: [{ dayOfWeek: "monday", localTime: "09:00" }],
          }),
        400,
        "invalid_medication",
      );

      const created = await treatmentPlans.createTreatmentPlan(ownerAppUserId, {
        medicationId,
        doseText: "one tablet",
        instructions: "after breakfast",
        startDate: "2030-01-07",
        endDate: "2030-01-07",
        timeZone: "Asia/Tehran",
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 45,
        schedules: [{ dayOfWeek: "monday", localTime: "09:00" }],
      });
      planId = String(created.id);
      assertEquals(created.patientUserId, ownerAppUserId);

      const persisted = await fixtureSql`
        select patient_user_id::text,patient_person_id::text
        from lifemate.treatment_plans
        where id=${planId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].patient_user_id, null);
      assertEquals(persisted[0].patient_person_id, ownerPersonId);

      const auditRows = await fixtureSql`
        select action,metadata_json
        from lifemate.audit_logs
        where resource_type='treatment_plan' and resource_id=${planId}::uuid
      `;
      assertEquals(auditRows.length, 1);
      assertEquals(auditRows[0].action, "treatment_plan.created");
      assertEquals(auditRows[0].metadata_json, null);

      // The public compatibility response is derived from authenticated request
      // context; authorization and reads do not depend on legacy ownership.
      const ownerRows = await treatmentPlans.listTreatmentPlans(ownerAppUserId);
      assertEquals(ownerRows.length, 1);
      assertEquals(ownerRows[0].id, planId);
      assertEquals(ownerRows[0].patientUserId, ownerAppUserId);

      const unrelatedRows = await treatmentPlans.listTreatmentPlans(
        otherAppUserId,
      );
      assertEquals(unrelatedRows.length, 0);

      await assertApiError(
        () => treatmentPlans.listTreatmentPlans(crypto.randomUUID()),
        409,
        "identity_person_mapping_missing",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
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
      await fixtureSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  const error = await assertRejects(action, ApiError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
}
