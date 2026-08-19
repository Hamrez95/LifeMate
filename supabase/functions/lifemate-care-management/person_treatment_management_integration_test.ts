import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createPersonTreatmentManagementStore } from "./person_treatment_management.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Care Management treatment tests.",
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

class TestApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

function apiError(status: number, code: string, message: string): Error {
  return new TestApiError(status, code, message);
}

function normalizeTreatment(
  body: Record<string, unknown>,
  editing: boolean,
) {
  return {
    version: editing ? Number(body.version) : 1,
    medicationVersion: editing ? Number(body.medicationVersion) : 1,
    medicationName: String(body.medicationName),
    strengthText: body.strengthText == null ? null : String(body.strengthText),
    form: body.form == null ? null : String(body.form),
    doseText: String(body.doseText),
    instructions: body.instructions == null ? null : String(body.instructions),
    startDate: String(body.startDate),
    endDate: body.endDate == null ? null : String(body.endDate),
    timeZone: String(body.timeZone),
    schedules: body.schedules as Array<
      { dayOfWeek: string; localTime: string }
    >,
    patientReminderMinutesBefore: Number(
      body.patientReminderMinutesBefore ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      body.caregiverReminderMinutesBefore ?? 60,
    ),
    status: String(body.status ?? "Active") === "Stopped"
      ? "Stopped" as const
      : "Active" as const,
  };
}

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

async function cleanup(identity: IdentityFixture): Promise<void> {
  await sql`
    delete from lifemate.audit_logs
    where actor_user_id=${identity.appUserId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from lifemate.dose_occurrences
    where patient_person_id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from lifemate.treatment_schedules
    where treatment_plan_id in (
      select id from lifemate.treatment_plans
      where patient_person_id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
    )
  `.catch(() => undefined);
  await sql`
    delete from lifemate.treatment_plans
    where patient_person_id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from lifemate.medications
    where owner_person_id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from core.account_person_links
    where account_id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
       or person_id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
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
    delete from core.person_profiles
    where person_id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
  `.catch(() => undefined);
  await sql`
    delete from core.persons
    where id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
  `.catch(() => undefined);
}

function createBody() {
  return {
    medicationName: "Caregiver medication",
    strengthText: "10 mg",
    form: "Tablet",
    doseText: "1 tablet",
    instructions: "After food",
    startDate: "2034-01-01",
    endDate: null,
    timeZone: "Asia/Tehran",
    schedules: [{ dayOfWeek: "monday", localTime: "09:00" }],
    patientReminderMinutesBefore: 30,
    caregiverReminderMinutesBefore: 60,
    status: "Active",
  };
}

Deno.test({
  name:
    "Care Management treatment writes and reads are Person-authoritative with AppUser response projection",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const patient = await createUnequalIdentity();
    const caregiver = await createUnequalIdentity();
    const otherPatient = await createUnequalIdentity();
    const store = createPersonTreatmentManagementStore({
      sql,
      normalizeTreatment,
      apiError,
    });

    try {
      const created = await store.createTreatmentPlan(
        caregiver.appUserId,
        patient.appUserId,
        createBody(),
      );
      const planId = String(created.id);
      const medicationId = String(
        (created.medication as Record<string, unknown>).id,
      );
      assertEquals(created.patientUserId, patient.appUserId);
      assertEquals(created.version, 1);

      const persisted = await sql`
        select
          p.patient_user_id::text as plan_user_id,
          p.patient_person_id::text as plan_person_id,
          m.owner_user_id::text as medication_user_id,
          m.owner_person_id::text as medication_person_id
        from lifemate.treatment_plans p
        join lifemate.medications m on m.id=p.medication_id
        where p.id=${planId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].plan_user_id, null);
      assertEquals(persisted[0].plan_person_id, patient.personId);
      assertEquals(persisted[0].medication_user_id, null);
      assertEquals(persisted[0].medication_person_id, patient.personId);

      const listed = await store.listTreatmentPlans(patient.appUserId);
      assertEquals(listed.length, 1);
      assertEquals(listed[0].patientUserId, patient.appUserId);
      assertEquals(listed[0].id, planId);
      assertEquals(
        (listed[0].medication as Record<string, unknown>).id,
        medicationId,
      );
      assertEquals(
        (await store.listTreatmentPlans(otherPatient.appUserId)).length,
        0,
      );

      const updated = await store.updateTreatmentPlan(
        caregiver.appUserId,
        patient.appUserId,
        planId,
        {
          ...createBody(),
          version: 1,
          medicationVersion: 1,
          medicationName: "Updated caregiver medication",
          status: "Stopped",
        },
      );
      assertEquals(updated.version, 2);
      assertEquals(updated.status, "stopped");
      assertEquals(updated.patientUserId, patient.appUserId);

      const persistedAfterUpdate = await sql`
        select
          p.patient_user_id::text as plan_user_id,
          p.patient_person_id::text as plan_person_id,
          m.owner_user_id::text as medication_user_id,
          m.owner_person_id::text as medication_person_id
        from lifemate.treatment_plans p
        join lifemate.medications m on m.id=p.medication_id
        where p.id=${planId}::uuid
      `;
      assertEquals(persistedAfterUpdate[0].plan_user_id, null);
      assertEquals(persistedAfterUpdate[0].plan_person_id, patient.personId);
      assertEquals(persistedAfterUpdate[0].medication_user_id, null);
      assertEquals(
        persistedAfterUpdate[0].medication_person_id,
        patient.personId,
      );

      const wrongPatientError = await assertRejects(
        () =>
          store.updateTreatmentPlan(
            caregiver.appUserId,
            otherPatient.appUserId,
            planId,
            {
              ...createBody(),
              version: 2,
              medicationVersion: 2,
            },
          ),
        TestApiError,
      );
      assertEquals(wrongPatientError.status, 404);
      assertEquals(wrongPatientError.code, "treatment_plan_not_found");

      await store.archiveTreatmentPlan(
        caregiver.appUserId,
        patient.appUserId,
        planId,
        2,
      );
      const archived = await sql`
        select status,patient_user_id::text,patient_person_id::text
        from lifemate.treatment_plans where id=${planId}::uuid
      `;
      assertEquals(archived[0].status, "Archived");
      assertEquals(archived[0].patient_user_id, null);
      assertEquals(archived[0].patient_person_id, patient.personId);

      const audits = await sql`
        select actor_user_id::text,action,metadata_json
        from lifemate.audit_logs
        where actor_user_id=${caregiver.appUserId}::uuid
          and resource_id=${planId}::uuid
        order by created_at_utc,action
      `;
      assertEquals(audits.length, 3);
      assertEquals(
        audits.every((row) => row.actor_user_id === caregiver.appUserId),
        true,
      );
      assertEquals(audits.every((row) => row.metadata_json == null), true);
    } finally {
      await cleanup(patient);
      await cleanup(caregiver);
      await cleanup(otherPatient);
      await sql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
