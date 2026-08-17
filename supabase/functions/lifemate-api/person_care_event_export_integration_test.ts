import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createDataExportStore } from "./data_export.ts";
import { createPersonCareEventStore } from "./person_care_events.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Person Care Event export tests.",
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
  name: "portable export selects Care Events by canonical Person ownership",
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
    const store = createPersonCareEventStore(databaseUrl);
    const exporter = createDataExportStore(databaseUrl);
    const targetDate = futureLocalDate();
    const ownerSentinel = `owner-care-export-${crypto.randomUUID()}`;
    const otherSentinel = `other-care-export-${crypto.randomUUID()}`;
    let ownerEventId: string | null = null;
    let otherEventId: string | null = null;

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

      const ownerEvent = await store.createCareEvent(ownerAppUserId, {
        clientRequestId: crypto.randomUUID(),
        eventType: "appointment",
        title: ownerSentinel,
        providerName: "Synthetic clinician",
        scheduledLocalDate: targetDate,
        scheduledLocalTime: "09:00",
        timeZone: "Asia/Tehran",
      });
      ownerEventId = String(ownerEvent.id);

      const otherEvent = await store.createCareEvent(otherAppUserId, {
        clientRequestId: crypto.randomUUID(),
        eventType: "appointment",
        title: otherSentinel,
        providerName: "Unrelated clinician",
        scheduledLocalDate: targetDate,
        scheduledLocalTime: "10:00",
        timeZone: "Asia/Tehran",
      });
      otherEventId = String(otherEvent.id);

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

      const exported = await exporter.exportAccountData(ownerAppUserId);
      assertEquals(exported.schemaVersion, "lifemate-portable-export-v1");
      const healthcare = exported.healthcare as Record<string, unknown>;
      const careEvents = healthcare.careEvents as Array<
        Record<string, unknown>
      >;

      assertEquals(careEvents.length, 1);
      assertEquals(careEvents[0].id, ownerEventId);
      assertEquals(careEvents[0].title, ownerSentinel);
      assertEquals(careEvents[0].createdBySelf, true);

      assert(otherEventId);
      const encoded = JSON.stringify(exported);
      assert(encoded.includes(ownerSentinel));
      assert(!encoded.includes(otherSentinel));
      assert(!encoded.includes(otherEventId));
      assert(!encoded.includes(ownerPersonId));
      assert(!encoded.includes(otherPersonId));

      // A privacy export must remain fail-closed when the canonical Self Person
      // mapping disappears instead of falling back to care_events.patient_user_id.
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
