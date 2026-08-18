import { assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createCareEventStore } from "./care_events.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for CareMate Care Event authorization tests.",
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
    ) values (
      ${appUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()
    )
  `;
  await sql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where legacy_app_user_id=${appUserId}::uuid
  `;
  await sql`
    insert into identity.accounts(id,legacy_app_user_id,status)
    values (${accountId}::uuid,${appUserId}::uuid,'Active')
  `;
  await sql`
    insert into core.persons(id,status,subject_category)
    values (${personId}::uuid,'Active','Adult')
  `;
  await sql`
    insert into core.account_person_links(account_id,person_id,link_type,status)
    values (${accountId}::uuid,${personId}::uuid,'Self','Active')
  `;

  return { appUserId, accountId, personId };
}

Deno.test({
  name:
    "CareMate Care Event authorization uses canonical Person and revocation fails closed",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const patient = await createUnequalIdentity();
    const caregiver = await createUnequalIdentity();
    const unrelated = await createUnequalIdentity();
    const relationshipId = crypto.randomUUID();
    const targetDate = futureLocalDate();
    const store = createCareEventStore(databaseUrl);
    let eventId: string | null = null;

    try {
      const event = await store.createCareEvent(patient.appUserId, {
        clientRequestId: crypto.randomUUID(),
        eventType: "appointment",
        title: "Canonical CareMate event",
        providerName: "Synthetic provider",
        scheduledLocalDate: targetDate,
        scheduledLocalTime: "09:00",
        timeZone: "Asia/Tehran",
      });
      eventId = String(event.id);

      await assertApiError(
        () =>
          store.listCareRecipientEvents(
            caregiver.appUserId,
            patient.appUserId,
            targetDate,
            targetDate,
          ),
        403,
        "care_access_denied",
      );

      await sql`
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

      const persisted = await sql`
        select patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${relationshipId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].patient_person_id, patient.personId);
      assertEquals(persisted[0].caregiver_person_id, caregiver.personId);

      const caregiverRows = await store.listCareRecipientEvents(
        caregiver.appUserId,
        patient.appUserId,
        targetDate,
        targetDate,
      );
      assertEquals(caregiverRows.length, 1);
      assertEquals(caregiverRows[0].id, eventId);
      assertEquals(caregiverRows[0].patientUserId, patient.appUserId);

      await assertApiError(
        () =>
          store.listCareRecipientEvents(
            unrelated.appUserId,
            patient.appUserId,
            targetDate,
            targetDate,
          ),
        403,
        "care_access_denied",
      );

      await sql`
        update lifemate.care_relationships
        set status='Revoked',
            revoked_by_user_id=${patient.appUserId}::uuid,
            revoked_at_utc=now(),
            updated_at_utc=now()
        where id=${relationshipId}::uuid
      `;

      await assertApiError(
        () =>
          store.listCareRecipientEvents(
            caregiver.appUserId,
            patient.appUserId,
            targetDate,
            targetDate,
          ),
        403,
        "care_access_denied",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await sql`
        delete from lifemate.care_relationships where id=${relationshipId}::uuid
      `.catch(() => undefined);
      if (eventId) {
        await sql`
          delete from lifemate.audit_logs
          where resource_type='care_event' and resource_id=${eventId}::uuid
        `.catch(() => undefined);
        await sql`
          delete from lifemate.care_events where id=${eventId}::uuid
        `.catch(() => undefined);
      }
      await sql.end({ timeout: 1 }).catch(() => undefined);
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
