import { assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createCareEventSyncStore } from "./care_event_sync.ts";
import { createPersonCareEventStore } from "./person_care_events.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for Care Event sync tests.");
}

const fixtureSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

async function createIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
): Promise<void> {
  await fixtureSql`
    insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
    values (${appUserId}::uuid,${crypto.randomUUID()},'Active',now(),now())
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
    delete from lifemate.care_events
    where patient_person_id=${personId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    delete from core.account_person_links
    where account_id=${accountId}::uuid or person_id=${personId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    update identity.accounts set legacy_app_user_id=null
    where id=${accountId}::uuid
  `.catch(() => undefined);
  await fixtureSql`delete from identity.accounts where id=${accountId}::uuid`
    .catch(() => undefined);
  await fixtureSql`delete from lifemate.app_users where id=${appUserId}::uuid`
    .catch(() => undefined);
  await fixtureSql`delete from core.persons where id=${personId}::uuid`
    .catch(() => undefined);
}

function eventBody(clientRequestId: string, title: string) {
  const date = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
  return {
    clientRequestId,
    eventType: "appointment",
    title,
    scheduledLocalDate: date,
    scheduledLocalTime: "09:00",
    timeZone: "Asia/Tehran",
  };
}

Deno.test({
  name: "Care Event incremental pull is Person-isolated and emits tombstones",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const ownerAppUserId = crypto.randomUUID();
    const ownerAccountId = crypto.randomUUID();
    const ownerPersonId = crypto.randomUUID();
    const otherAppUserId = crypto.randomUUID();
    const otherAccountId = crypto.randomUUID();
    const otherPersonId = crypto.randomUUID();
    const eventStore = createPersonCareEventStore(databaseUrl);
    const syncStore = createCareEventSyncStore(databaseUrl);
    let ownerEventId = "";
    let otherEventId = "";

    try {
      await createIdentity(ownerAppUserId, ownerAccountId, ownerPersonId);
      await createIdentity(otherAppUserId, otherAccountId, otherPersonId);

      const ownerEvent = await eventStore.createCareEvent(
        ownerAppUserId,
        eventBody(crypto.randomUUID(), "Owner fixture"),
      );
      ownerEventId = String(ownerEvent.id);
      const otherEvent = await eventStore.createCareEvent(
        otherAppUserId,
        eventBody(crypto.randomUUID(), "Other fixture"),
      );
      otherEventId = String(otherEvent.id);
      assertNotEquals(ownerEventId, otherEventId);

      const first = await syncStore.pullOwnerCareEvents(
        ownerAppUserId,
        null,
        1,
      );
      assertEquals(first.changes.length, 1);
      assertEquals(first.changes[0].recordKey, ownerEventId);
      assertEquals(first.changes[0].deleted, false);
      assertEquals(first.changes[0].payload?.patientUserId, undefined);
      assertEquals(
        first.changes.some((change) => change.recordKey === otherEventId),
        false,
      );

      await fixtureSql`
        update lifemate.care_events
        set status='Cancelled',version=version+1,updated_at_utc=now() + interval '1 second'
        where id=${ownerEventId}::uuid
      `;

      const second = await syncStore.pullOwnerCareEvents(
        ownerAppUserId,
        first.nextCursor,
        10,
      );
      assertEquals(second.changes.length, 1);
      assertEquals(second.changes[0].recordKey, ownerEventId);
      assertEquals(second.changes[0].deleted, true);
      assertEquals(second.changes[0].payload, null);

      const unrelated = await syncStore.pullOwnerCareEvents(
        otherAppUserId,
        null,
        10,
      );
      assertEquals(unrelated.changes.length, 1);
      assertEquals(unrelated.changes[0].recordKey, otherEventId);
    } finally {
      await cleanupIdentity(ownerAppUserId, ownerAccountId, ownerPersonId);
      await cleanupIdentity(otherAppUserId, otherAccountId, otherPersonId);
      await closeLifeMateSqlClientsForTest();
    }
  },
});

Deno.test({
  name: "Care Event sync rejects an identity without Self Person mapping",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const syncStore = createCareEventSyncStore(databaseUrl);
    const unknownAppUserId = crypto.randomUUID();
    let status = 0;
    let code = "";
    try {
      await syncStore.pullOwnerCareEvents(unknownAppUserId, null, 10);
    } catch (error) {
      const value = error as { status?: number; code?: string };
      status = value.status ?? 0;
      code = value.code ?? "";
    } finally {
      await closeLifeMateSqlClientsForTest();
    }
    assertEquals(status, 409);
    assertEquals(code, "identity_person_mapping_missing");
  },
});
