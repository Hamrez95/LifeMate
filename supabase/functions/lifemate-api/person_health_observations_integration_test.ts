import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createDataExportStore } from "./data_export.ts";
import { createHealthObservationStore } from "./health_observations.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Person Health Observation tests.",
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
    "Health Observation runtime and export remain Person-authoritative after legacy owner freeze",
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
    const clientRequestId = crypto.randomUUID();
    const otherSentinel = `unrelated-health-${crypto.randomUUID()}`;
    const store = createHealthObservationStore(databaseUrl);
    const exporter = createDataExportStore(databaseUrl);
    let observationId: string | null = null;
    let otherObservationId: string | null = null;

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

    const observedAtUtc = new Date(Date.now() - 60_000).toISOString();
    const observedLocalDate = observedAtUtc.slice(0, 10);
    const body = {
      clientRequestId,
      observationType: "heart_rate",
      valuePrimary: 72,
      observedAtUtc,
      observedLocalDate,
      timeZone: "Asia/Tehran",
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

      const created = await store.createOwnerObservation(ownerAppUserId, body);
      observationId = String(created.id);
      assertEquals(created.personId, ownerPersonId);
      assertEquals(created.sourceApplicationCode, "wellmate");

      const retried = await store.createOwnerObservation(ownerAppUserId, body);
      assertEquals(retried.id, observationId);
      assertEquals(retried.personId, ownerPersonId);

      const persisted = await fixtureSql`
        select owner_user_id::text,person_id::text,
               recorded_by_account_id::text,source_application_id::text
        from lifemate.health_observations
        where id=${observationId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].owner_user_id, null);
      assertEquals(persisted[0].person_id, ownerPersonId);
      assertEquals(persisted[0].recorded_by_account_id, ownerAccountId);
      assertNotEquals(persisted[0].recorded_by_account_id, ownerAppUserId);

      const ownerRows = await store.listOwnerObservations(
        ownerAppUserId,
        observedLocalDate,
        observedLocalDate,
      );
      assertEquals(ownerRows.length, 1);
      assertEquals(ownerRows[0].id, observationId);
      assertEquals(ownerRows[0].personId, ownerPersonId);

      const unrelatedRows = await store.listOwnerObservations(
        otherAppUserId,
        observedLocalDate,
        observedLocalDate,
      );
      assertEquals(unrelatedRows.length, 0);

      await assertApiError(
        () => store.deleteOwnerObservation(otherAppUserId, observationId!),
        404,
        "health_observation_not_found",
      );

      const otherCreated = await store.createOwnerObservation(otherAppUserId, {
        clientRequestId: crypto.randomUUID(),
        observationType: "note",
        note: otherSentinel,
        observedAtUtc,
        observedLocalDate,
        timeZone: "Asia/Tehran",
      });
      otherObservationId = String(otherCreated.id);

      const exported = await exporter.exportAccountData(ownerAppUserId);
      assertEquals(exported.schemaVersion, "lifemate-portable-export-v1");
      const healthcare = exported.healthcare as Record<string, unknown>;
      const exportedObservations = healthcare.healthObservations as Array<
        Record<string, unknown>
      >;
      assertEquals(exportedObservations.length, 1);
      assertEquals(exportedObservations[0].id, observationId);
      assertEquals(exportedObservations[0].recordedBySelf, true);
      const encodedHealthcare = JSON.stringify(exportedObservations);
      assertEquals(encodedHealthcare.includes(otherSentinel), false);
      assertEquals(encodedHealthcare.includes(otherObservationId), false);
      assertEquals(encodedHealthcare.includes(ownerPersonId), false);
      assertEquals(encodedHealthcare.includes(otherPersonId), false);
      assertEquals(encodedHealthcare.includes(otherAccountId), false);
      assertEquals(encodedHealthcare.includes(otherAppUserId), false);

      await assertApiError(
        () =>
          store.listOwnerObservations(
            crypto.randomUUID(),
            observedLocalDate,
            observedLocalDate,
          ),
        409,
        "self_person_missing",
      );

      await store.deleteOwnerObservation(ownerAppUserId, observationId);
      const afterDelete = await fixtureSql`
        select id from lifemate.health_observations
        where id=${observationId}::uuid
      `;
      assertEquals(afterDelete.length, 0);

      const auditRows = await fixtureSql`
        select actor_user_id::text,action
        from lifemate.audit_logs
        where resource_type='health_observation'
          and resource_id=${observationId}::uuid
        order by created_at_utc, action
      `;
      assertEquals(auditRows.length, 2);
      assertEquals(auditRows[0].actor_user_id, ownerAppUserId);
      assertEquals(auditRows[1].actor_user_id, ownerAppUserId);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      for (const id of [observationId, otherObservationId]) {
        if (!id) continue;
        await fixtureSql`
          delete from lifemate.audit_logs
          where resource_type='health_observation' and resource_id=${id}::uuid
        `.catch(() => undefined);
        await fixtureSql`
          delete from lifemate.health_observations where id=${id}::uuid
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
