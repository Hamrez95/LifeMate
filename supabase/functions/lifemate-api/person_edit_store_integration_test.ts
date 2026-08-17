import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPersonCareEventStore } from "./person_care_events.ts";
import { createPersonEditStore } from "./edit_store.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for Person edit-store tests.");
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
    "healthcare edit runtime remains Person-authoritative after legacy write freeze",
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

    for (
      const [appUserId, accountId, personId] of [
        [ownerAppUserId, ownerAccountId, ownerPersonId],
        [otherAppUserId, otherAccountId, otherPersonId],
      ]
    ) {
      assertNotEquals(appUserId, accountId);
      assertNotEquals(appUserId, personId);
      assertNotEquals(accountId, personId);
    }

    const medications = createPersonMedicationStore(databaseUrl);
    const treatmentPlans = createPersonTreatmentPlanStore(databaseUrl);
    const careEvents = createPersonCareEventStore(databaseUrl);
    const edits = createPersonEditStore(databaseUrl);
    let medicationId: string | null = null;
    let treatmentPlanId: string | null = null;
    let careEventId: string | null = null;

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
        name: "Edit ownership fixture",
        strengthText: "10 mg",
        form: "tablet",
        notes: "Person edit regression fixture",
      });
      medicationId = String(medication.id);

      const treatment = await treatmentPlans.createTreatmentPlan(
        ownerAppUserId,
        {
          medicationId,
          doseText: "one tablet",
          instructions: "after breakfast",
          startDate: "2030-01-07",
          endDate: "2030-01-14",
          timeZone: "Asia/Tehran",
          patientReminderMinutesBefore: 15,
          caregiverReminderMinutesBefore: 45,
          schedules: [{ dayOfWeek: "monday", localTime: "09:00" }],
        },
      );
      treatmentPlanId = String(treatment.id);

      // Medication is already legacy-null on create. Simulate the next staged
      // Treatment write freeze as well: edit ownership must not read either
      // legacy ownership column.
      await fixtureSql`
        update lifemate.treatment_plans
        set patient_user_id=null
        where id=${treatmentPlanId}::uuid
      `;
      const legacyOwnership = await fixtureSql`
        select p.patient_user_id::text,m.owner_user_id::text,
               p.patient_person_id::text,m.owner_person_id::text
        from lifemate.treatment_plans p
        join lifemate.medications m on m.id=p.medication_id
        where p.id=${treatmentPlanId}::uuid
      `;
      assertEquals(legacyOwnership[0].patient_user_id, null);
      assertEquals(legacyOwnership[0].owner_user_id, null);
      assertEquals(legacyOwnership[0].patient_person_id, ownerPersonId);
      assertEquals(legacyOwnership[0].owner_person_id, ownerPersonId);

      const treatmentMedication = treatment.medication as Record<
        string,
        unknown
      >;
      await assertApiError(
        () =>
          edits.updateTreatmentPlan(otherAppUserId, treatmentPlanId, {
            version: treatment.version,
            medicationVersion: treatmentMedication.version,
            medicationName: "Forbidden edit",
            strengthText: "20 mg",
            form: "tablet",
            doseText: "two tablets",
            instructions: "should fail",
            startDate: "2030-01-07",
            endDate: "2030-01-14",
            timeZone: "Asia/Tehran",
            schedules: [{ dayOfWeek: "monday", localTime: "10:00" }],
            status: "active",
          }),
        404,
        "treatment_plan_not_found",
      );

      const updatedTreatment = await edits.updateTreatmentPlan(
        ownerAppUserId,
        treatmentPlanId,
        {
          version: treatment.version,
          medicationVersion: treatmentMedication.version,
          medicationName: "Person-owned edited medication",
          strengthText: "20 mg",
          form: "tablet",
          doseText: "two tablets",
          instructions: "after dinner",
          startDate: "2030-01-07",
          endDate: "2030-01-14",
          timeZone: "Asia/Tehran",
          patientReminderMinutesBefore: 20,
          caregiverReminderMinutesBefore: 50,
          schedules: [{ dayOfWeek: "monday", localTime: "10:00" }],
          status: "active",
        },
      );
      assertEquals(updatedTreatment.patientUserId, ownerAppUserId);
      assertEquals(updatedTreatment.doseText, "two tablets");
      assertEquals(
        (updatedTreatment.medication as Record<string, unknown>).name,
        "Person-owned edited medication",
      );

      const targetDate = futureLocalDate();
      const careEvent = await careEvents.createCareEvent(ownerAppUserId, {
        clientRequestId: crypto.randomUUID(),
        eventType: "appointment",
        title: "Editable Person-owned appointment",
        providerName: "Synthetic clinician",
        specialty: "integration",
        reason: "Person edit regression fixture",
        scheduledLocalDate: targetDate,
        scheduledLocalTime: "09:00",
        timeZone: "Asia/Tehran",
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 45,
      });
      careEventId = String(careEvent.id);

      const persistedCareEvent = await fixtureSql`
        select patient_user_id::text,patient_person_id::text,
               created_by_user_id::text
        from lifemate.care_events
        where id=${careEventId}::uuid
      `;
      assertEquals(persistedCareEvent[0].patient_user_id, null);
      assertEquals(persistedCareEvent[0].patient_person_id, ownerPersonId);
      assertEquals(persistedCareEvent[0].created_by_user_id, ownerAppUserId);

      const fetched = await edits.getCareEvent(ownerAppUserId, careEventId);
      assertEquals(fetched.id, careEventId);
      assertEquals(fetched.patientUserId, ownerAppUserId);
      await assertApiError(
        () => edits.getCareEvent(otherAppUserId, careEventId),
        404,
        "care_event_not_found",
      );

      const updatedCareEvent = await edits.updateCareEvent(
        ownerAppUserId,
        careEventId,
        {
          version: careEvent.version,
          eventType: "appointment",
          title: "Edited Person-owned appointment",
          providerName: "Synthetic clinician",
          specialty: "integration",
          reason: "updated fixture",
          scheduledLocalDate: targetDate,
          scheduledLocalTime: "10:30",
          timeZone: "Asia/Tehran",
          patientReminderMinutesBefore: 20,
          caregiverReminderMinutesBefore: 50,
          status: "scheduled",
        },
      );
      assertEquals(updatedCareEvent.patientUserId, ownerAppUserId);
      assertEquals(updatedCareEvent.title, "Edited Person-owned appointment");
      assertEquals(updatedCareEvent.createdByUserId, ownerAppUserId);

      const auditRows = await fixtureSql`
        select actor_user_id::text,action,resource_type
        from lifemate.audit_logs
        where resource_id in (${treatmentPlanId}::uuid,${careEventId}::uuid)
          and action in ('treatment_plan.updated','care_event.updated')
        order by action
      `;
      assertEquals(auditRows.length, 2);
      assertEquals(auditRows[0].actor_user_id, ownerAppUserId);
      assertEquals(auditRows[1].actor_user_id, ownerAppUserId);

      await assertApiError(
        () => edits.getCareEvent(crypto.randomUUID(), careEventId),
        409,
        "identity_person_mapping_missing",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      if (careEventId) {
        await fixtureSql`
          delete from lifemate.audit_logs
          where resource_type='care_event' and resource_id=${careEventId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.care_events where id=${careEventId}::uuid
        `.catch(() => undefined);
      }
      if (treatmentPlanId) {
        await fixtureSql`
          delete from lifemate.dose_occurrences
          where treatment_plan_id=${treatmentPlanId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.treatment_schedules
          where treatment_plan_id=${treatmentPlanId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.audit_logs
          where resource_type='treatment_plan'
            and resource_id=${treatmentPlanId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.treatment_plans where id=${treatmentPlanId}::uuid
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

function futureLocalDate(): string {
  return new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}
