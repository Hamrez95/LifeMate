import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPersonMedicationStore } from "./person_medications.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for person medication tests.");
}

const adminSql = postgres(databaseUrl, {
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
  await adminSql`
    insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
    values (${appUserId}::uuid,${authSubject},'Active',now(),now())
  `;

  // Preserve the bootstrap Account/Person rows instead of deleting dependent
  // commerce/ecosystem data. Only detach the legacy AppUser mapping, then add
  // the intentionally different canonical Account -> Self Person mapping. This
  // keeps the fixture runnable by the restricted Edge role without granting it
  // unrelated delete privileges merely for test setup.
  await adminSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${appUserId}::uuid
  `;
  await adminSql`
    insert into identity.accounts(id,legacy_app_user_id,status)
    values (${accountId}::uuid,${appUserId}::uuid,'Active')
  `;
  await adminSql`
    insert into core.persons(id,status,subject_category)
    values (${personId}::uuid,'Active','Adult')
  `;
  await adminSql`
    insert into core.account_person_links(account_id,person_id,link_type,status)
    values (${accountId}::uuid,${personId}::uuid,'Self','Active')
  `;
}

async function cleanupIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
): Promise<void> {
  await adminSql`
    delete from core.account_person_links
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
       or person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from identity.accounts
    where id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from lifemate.app_users where id=${appUserId}::uuid
  `.catch(() => undefined);
  await adminSql`
    delete from core.persons
    where id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
}

Deno.test({
  name:
    "medication runtime authorizes by canonical Person during legacy dual-write",
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
    const store = createPersonMedicationStore(databaseUrl);
    let medicationId: string | null = null;

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

      const created = await store.createMedication(ownerAppUserId, {
        name: "Person-owned test medication",
        strengthText: "10 mg",
        form: "tablet",
        notes: "synthetic integration fixture",
      });
      medicationId = String(created.id);

      const persisted = await adminSql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.medications
        where id=${medicationId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].owner_user_id, ownerAppUserId);
      assertEquals(persisted[0].owner_person_id, ownerPersonId);

      // Simulate the final legacy-column freeze. The Person-authoritative read
      // must keep working even after owner_user_id is retired.
      await adminSql`
        update lifemate.medications
        set owner_user_id=null
        where id=${medicationId}::uuid
      `;

      const ownerRows = await store.listMedications(ownerAppUserId);
      assertEquals(ownerRows.length, 1);
      assertEquals(ownerRows[0].id, medicationId);

      const unrelatedRows = await store.listMedications(otherAppUserId);
      assertEquals(unrelatedRows.length, 0);

      await assertRejects(
        () => store.listMedications(crypto.randomUUID()),
        Error,
        "person mapping",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      if (medicationId) {
        await adminSql`
          delete from lifemate.audit_logs
          where resource_type='medication' and resource_id=${medicationId}::uuid
        `.catch(() => undefined);
        await adminSql`
          delete from lifemate.medications where id=${medicationId}::uuid
        `.catch(() => undefined);
      }
      await cleanupIdentity(ownerAppUserId, ownerAccountId, ownerPersonId);
      await cleanupIdentity(otherAppUserId, otherAccountId, otherPersonId);
      await adminSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
