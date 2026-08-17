import { assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPersonCareEventStore } from "./person_care_events.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for Person Care Event tests.");
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
  name: "Care Event runtime scopes idempotency and reads to canonical Person",
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
    const clientRequestId = crypto.randomUUID();
    const store = createPersonCareEventStore(databaseUrl);
    const targetDate = futureLocalDate();
    let ownerEventId: string | null = null;
    let otherEventId: string | null = null;

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

    const ownerBody = {
      clientRequestId,
      eventType: "appointment",
      title: "Person-owned appointment",
      providerName: "Synthetic clinician",
      specialty: "integration",
      reason: "Person ownership fixture",
      scheduledLocalDate: targetDate,
      scheduledLocalTime: "09:00",
      timeZone: "Asia/Tehran",
      patientReminderMinutesBefore: 15,
      caregiverReminderMinutesBefore: 45,
    };

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

      const created = await store.createCareEvent(ownerAppUserId, ownerBody);
      ownerEventId = String(created.id);
      assertEquals(created.patientUserId, ownerAppUserId);

      const retried = await store.createCareEvent(ownerAppUserId, ownerBody);
      assertEquals(retried.id, ownerEventId);
      assertEquals(retried.patientUserId, ownerAppUserId);

      await assertApiError(
        () =>
          store.createCareEvent(ownerAppUserId, {
            ...ownerBody,
            title: "Conflicting retry",
          }),
        409,
        "idempotency_key_reused",
      );

      // Exercise an independent canonical Person idempotency scope: an
      // unrelated Person may use the same client request id without colliding
      // with the owner's Person-scoped key.
      const otherCreated = await store.createCareEvent(otherAppUserId, {
        ...ownerBody,
        title: "Unrelated Person appointment",
      });
      otherEventId = String(otherCreated.id);
      assertNotEquals(otherEventId, ownerEventId);

      const persisted = await fixtureSql`
        select patient_user_id::text,patient_person_id::text,
               created_by_user_id::text
        from lifemate.care_events
        where id=${ownerEventId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].patient_user_id, null);
      assertEquals(persisted[0].patient_person_id, ownerPersonId);
      assertEquals(persisted[0].created_by_user_id, ownerAppUserId);
      assertNotEquals(persisted[0].created_by_user_id, ownerPersonId);

      const auditRows = await fixtureSql`
        select actor_user_id::text,action,metadata_json
        from lifemate.audit_logs
        where resource_type='care_event' and resource_id=${ownerEventId}::uuid
      `;
      assertEquals(auditRows.length, 1);
      assertEquals(auditRows[0].actor_user_id, ownerAppUserId);
      assertEquals(auditRows[0].action, "care_event.created");
      assertEquals(
        auditRows[0].metadata_json,
        JSON.stringify({ eventType: "Appointment" }),
      );

      const ownerRows = await store.listCareEvents(
        ownerAppUserId,
        targetDate,
        targetDate,
      );
      assertEquals(ownerRows.length, 1);
      assertEquals(ownerRows[0].id, ownerEventId);
      assertEquals(ownerRows[0].patientUserId, ownerAppUserId);

      const unrelatedRows = await store.listCareEvents(
        otherAppUserId,
        targetDate,
        targetDate,
      );
      assertEquals(unrelatedRows.length, 1);
      assertEquals(unrelatedRows[0].id, otherEventId);
      assertNotEquals(unrelatedRows[0].id, ownerEventId);

      await assertApiError(
        () =>
          store.listCareRecipientEvents(
            caregiverAppUserId,
            ownerAppUserId,
            targetDate,
            targetDate,
          ),
        403,
        "care_access_denied",
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

      const caregiverRows = await store.listCareRecipientEvents(
        caregiverAppUserId,
        ownerAppUserId,
        targetDate,
        targetDate,
      );
      assertEquals(caregiverRows.length, 1);
      assertEquals(caregiverRows[0].id, ownerEventId);
      assertEquals(caregiverRows[0].patientUserId, ownerAppUserId);

      // The row was created legacy-null. Owner and caregiver reads, including
      // the public patientUserId field, must stay independent of the nullable
      // patient_user_id compatibility column.
      const ownerAfterFreeze = await store.listCareEvents(
        ownerAppUserId,
        targetDate,
        targetDate,
      );
      assertEquals(ownerAfterFreeze.length, 1);
      assertEquals(ownerAfterFreeze[0].id, ownerEventId);
      assertEquals(ownerAfterFreeze[0].patientUserId, ownerAppUserId);

      const caregiverAfterFreeze = await store.listCareRecipientEvents(
        caregiverAppUserId,
        ownerAppUserId,
        targetDate,
        targetDate,
      );
      assertEquals(caregiverAfterFreeze.length, 1);
      assertEquals(caregiverAfterFreeze[0].id, ownerEventId);
      assertEquals(caregiverAfterFreeze[0].patientUserId, ownerAppUserId);

      await assertApiError(
        () =>
          store.listCareEvents(
            crypto.randomUUID(),
            targetDate,
            targetDate,
          ),
        409,
        "identity_person_mapping_missing",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await fixtureSql`
        delete from lifemate.care_relationships where id=${relationshipId}::uuid
      `.catch(() => undefined);
      for (const eventId of [ownerEventId, otherEventId]) {
        if (!eventId) continue;
        await fixtureSql`
          delete from lifemate.audit_logs
          where resource_type='care_event' and resource_id=${eventId}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.care_events where id=${eventId}::uuid
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

function futureLocalDate(): string {
  const future = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = Object.fromEntries(
    formatter.formatToParts(future).map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
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
