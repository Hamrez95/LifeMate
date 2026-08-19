import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createPersonCareEventManagementStore } from "./person_care_event_management.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Care Management Care Event tests.",
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

function normalizeCareEvent(
  body: Record<string, unknown>,
  editing: boolean,
) {
  return {
    version: editing ? Number(body.version) : 1,
    clientRequestId: editing
      ? crypto.randomUUID()
      : String(body.clientRequestId),
    eventType: String(body.eventType).toLowerCase() === "injection"
      ? "Injection" as const
      : "Appointment" as const,
    title: String(body.title),
    providerName: body.providerName == null ? null : String(body.providerName),
    specialty: body.specialty == null ? null : String(body.specialty),
    medicationName: body.medicationName == null
      ? null
      : String(body.medicationName),
    doseText: body.doseText == null ? null : String(body.doseText),
    administrationRoute: body.administrationRoute == null
      ? null
      : String(body.administrationRoute),
    reason: body.reason == null ? null : String(body.reason),
    instructions: body.instructions == null ? null : String(body.instructions),
    centerName: body.centerName == null ? null : String(body.centerName),
    addressLine: body.addressLine == null ? null : String(body.addressLine),
    phoneNumber: body.phoneNumber == null ? null : String(body.phoneNumber),
    scheduledLocalDate: String(body.scheduledLocalDate),
    scheduledLocalTime: String(body.scheduledLocalTime),
    timeZone: String(body.timeZone),
    patientReminderMinutesBefore: Number(
      body.patientReminderMinutesBefore ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      body.caregiverReminderMinutesBefore ?? 60,
    ),
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
    delete from lifemate.care_events
    where patient_person_id in (${identity.appUserId}::uuid,${identity.personId}::uuid)
       or created_by_user_id=${identity.appUserId}::uuid
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

function createBody(clientRequestId = crypto.randomUUID()) {
  return {
    clientRequestId,
    eventType: "appointment",
    title: "Caregiver appointment",
    providerName: "Test clinician",
    specialty: "General",
    medicationName: null,
    doseText: null,
    administrationRoute: null,
    reason: "Checkup",
    instructions: "Bring reports",
    centerName: "Test center",
    addressLine: "Test address",
    phoneNumber: null,
    scheduledLocalDate: "2034-02-01",
    scheduledLocalTime: "10:30",
    timeZone: "Asia/Tehran",
    patientReminderMinutesBefore: 30,
    caregiverReminderMinutesBefore: 60,
  };
}

Deno.test({
  name:
    "Care Management Care Events are Person-authoritative while caregiver provenance and AppUser projection remain",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const patient = await createUnequalIdentity();
    const caregiver = await createUnequalIdentity();
    const otherPatient = await createUnequalIdentity();
    const store = createPersonCareEventManagementStore({
      sql,
      normalizeCareEvent,
      apiError,
    });

    try {
      const clientRequestId = crypto.randomUUID();
      const created = await store.createCareEvent(
        caregiver.appUserId,
        patient.appUserId,
        createBody(clientRequestId),
      );
      const eventId = String(created.id);
      assertEquals(created.patientUserId, patient.appUserId);
      assertEquals(created.version, 1);

      const replay = await store.createCareEvent(
        caregiver.appUserId,
        patient.appUserId,
        createBody(clientRequestId),
      );
      assertEquals(replay.id, eventId);
      const countRows = await sql`
        select count(*)::integer as count
        from lifemate.care_events
        where patient_person_id=${patient.personId}::uuid
          and client_request_id=${clientRequestId}::uuid
      `;
      assertEquals(countRows[0].count, 1);

      const persisted = await sql`
        select patient_user_id::text,patient_person_id::text,
               created_by_user_id::text,provenance_source
        from lifemate.care_events
        where id=${eventId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].patient_user_id, null);
      assertEquals(persisted[0].patient_person_id, patient.personId);
      assertEquals(persisted[0].created_by_user_id, caregiver.appUserId);
      assertEquals(persisted[0].provenance_source, "CaregiverInput");

      const listed = await store.listCareEvents(patient.appUserId);
      assertEquals(listed.length, 1);
      assertEquals(listed[0].id, eventId);
      assertEquals(listed[0].patientUserId, patient.appUserId);
      assertEquals(
        (await store.listCareEvents(otherPatient.appUserId)).length,
        0,
      );

      const updated = await store.updateCareEvent(
        caregiver.appUserId,
        patient.appUserId,
        eventId,
        {
          ...createBody(),
          version: 1,
          title: "Updated caregiver appointment",
        },
      );
      assertEquals(updated.version, 2);
      assertEquals(updated.title, "Updated caregiver appointment");
      assertEquals(updated.patientUserId, patient.appUserId);

      const persistedAfterUpdate = await sql`
        select patient_user_id::text,patient_person_id::text,
               created_by_user_id::text
        from lifemate.care_events
        where id=${eventId}::uuid
      `;
      assertEquals(persistedAfterUpdate[0].patient_user_id, null);
      assertEquals(
        persistedAfterUpdate[0].patient_person_id,
        patient.personId,
      );
      assertEquals(
        persistedAfterUpdate[0].created_by_user_id,
        caregiver.appUserId,
      );

      const wrongPatientError = await assertRejects(
        () =>
          store.updateCareEvent(
            caregiver.appUserId,
            otherPatient.appUserId,
            eventId,
            { ...createBody(), version: 2 },
          ),
        TestApiError,
      );
      assertEquals(wrongPatientError.status, 404);
      assertEquals(wrongPatientError.code, "care_event_not_found");

      await store.cancelCareEvent(
        caregiver.appUserId,
        patient.appUserId,
        eventId,
        2,
      );
      const cancelled = await sql`
        select status,patient_user_id::text,patient_person_id::text,
               created_by_user_id::text,version
        from lifemate.care_events
        where id=${eventId}::uuid
      `;
      assertEquals(cancelled[0].status, "Cancelled");
      assertEquals(cancelled[0].version, 3);
      assertEquals(cancelled[0].patient_user_id, null);
      assertEquals(cancelled[0].patient_person_id, patient.personId);
      assertEquals(cancelled[0].created_by_user_id, caregiver.appUserId);

      const audits = await sql`
        select actor_user_id::text,action,metadata_json
        from lifemate.audit_logs
        where actor_user_id=${caregiver.appUserId}::uuid
          and resource_id=${eventId}::uuid
        order by created_at_utc,action
      `;
      assertEquals(audits.length, 3);
      assertEquals(
        audits.every((row) => row.actor_user_id === caregiver.appUserId),
        true,
      );
      const encodedAudit = JSON.stringify(audits);
      assertEquals(encodedAudit.includes(patient.appUserId), false);
      assertEquals(encodedAudit.includes(patient.accountId), false);
      assertEquals(encodedAudit.includes(patient.personId), false);
    } finally {
      await cleanup(patient);
      await cleanup(caregiver);
      await cleanup(otherPatient);
      await sql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
