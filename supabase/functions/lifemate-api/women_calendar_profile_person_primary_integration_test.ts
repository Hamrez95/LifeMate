import { assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPersonWomenCalendarStore } from "./person_women_calendar.ts";
import { createWomenCalendarStore as createLegacyWomenCalendarStore } from "./women_calendar_legacy.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Women profile Person-primary tests.",
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
       or resource_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from lifemate.women_calendar_daily_logs
    where owner_person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from lifemate.women_calendar_episodes
    where owner_person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from lifemate.women_calendar_profiles
    where owner_person_id=${identity.personId}::uuid
       or owner_user_id=${identity.appUserId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from core.account_person_links
    where account_id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
       or person_id=${identity.personId}::uuid
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
    delete from core.person_profiles where person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await sql`
    delete from core.persons where id=${identity.personId}::uuid
  `.catch(() => undefined);
}

Deno.test({
  name:
    "Women profile primary key and audit resource are Person while legacy lookup remains rollback-compatible",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const canonical = await createUnequalIdentity();
    const legacy = await createUnequalIdentity();
    const personStore = createPersonWomenCalendarStore(databaseUrl);
    const legacyStore = createLegacyWomenCalendarStore(databaseUrl);

    try {
      const pkRows = await sql`
        select kcu.column_name
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on kcu.constraint_schema=tc.constraint_schema
         and kcu.constraint_name=tc.constraint_name
         and kcu.table_name=tc.table_name
        where tc.table_schema='lifemate'
          and tc.table_name='women_calendar_profiles'
          and tc.constraint_type='PRIMARY KEY'
        order by kcu.ordinal_position
      `;
      assertEquals(
        pkRows.map((row) => String(row.column_name)),
        ["owner_person_id"],
      );

      const columns = await sql`
        select column_name,is_nullable
        from information_schema.columns
        where table_schema='lifemate'
          and table_name='women_calendar_profiles'
          and column_name in ('owner_user_id','owner_person_id')
        order by column_name
      `;
      assertEquals(
        columns.map((row) => ({
          column: String(row.column_name),
          nullable: String(row.is_nullable),
        })),
        [
          { column: "owner_person_id", nullable: "NO" },
          { column: "owner_user_id", nullable: "YES" },
        ],
      );

      const legacyIndex = await sql`
        select indexdef
        from pg_indexes
        where schemaname='lifemate'
          and tablename='women_calendar_profiles'
          and indexname='uq_women_calendar_profile_owner_user'
      `;
      assertEquals(legacyIndex.length, 1);
      assertEquals(
        String(legacyIndex[0].indexdef).includes("owner_user_id"),
        true,
      );

      const canonicalProfile = await personStore.updateOwnerProfile(
        canonical.appUserId,
        {
          version: 0,
          enabled: true,
          lastPeriodStart: "2032-01-01",
          cycleLength: 28,
          periodLength: 5,
          remindersEnabled: true,
        },
      );
      assertEquals(canonicalProfile.ownerUserId, canonical.appUserId);

      const canonicalRow = await sql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.women_calendar_profiles
        where owner_person_id=${canonical.personId}::uuid
      `;
      // Identity-34 retires the redundant AppUser storage for canonical writes;
      // Person remains the physical primary/canonical ownership key.
      assertEquals(canonicalRow[0]?.owner_user_id, null);
      assertEquals(canonicalRow[0]?.owner_person_id, canonical.personId);

      const canonicalAudit = await sql`
        select actor_user_id::text,resource_id::text
        from lifemate.audit_logs
        where action='women_calendar.profile_created'
          and actor_user_id=${canonical.appUserId}::uuid
        order by created_at_utc desc
        limit 1
      `;
      assertEquals(canonicalAudit[0]?.actor_user_id, canonical.appUserId);
      assertEquals(canonicalAudit[0]?.resource_id, canonical.personId);

      // Old AppUser-only backend path remains usable during staged rollout. The
      // existing ownership compatibility trigger maps the legacy insert to Person.
      const legacyProfile = await legacyStore.updateOwnerProfile(
        legacy.appUserId,
        {
          version: 0,
          enabled: true,
          lastPeriodStart: "2032-02-01",
          cycleLength: 30,
          periodLength: 6,
          remindersEnabled: true,
        },
      );
      assertEquals(legacyProfile.ownerUserId, legacy.appUserId);

      const legacyRow = await sql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.women_calendar_profiles
        where owner_person_id=${legacy.personId}::uuid
      `;
      assertEquals(legacyRow[0]?.owner_user_id, legacy.appUserId);
      assertEquals(legacyRow[0]?.owner_person_id, legacy.personId);

      const legacyAudit = await sql`
        select actor_user_id::text,resource_id::text
        from lifemate.audit_logs
        where action='women_calendar.profile_created'
          and actor_user_id=${legacy.appUserId}::uuid
        order by created_at_utc desc
        limit 1
      `;
      assertEquals(legacyAudit[0]?.actor_user_id, legacy.appUserId);
      assertEquals(legacyAudit[0]?.resource_id, legacy.personId);

      const legacyUpdate = await legacyStore.updateOwnerProfile(
        legacy.appUserId,
        {
          version: 1,
          enabled: true,
          lastPeriodStart: "2032-02-02",
          cycleLength: 30,
          periodLength: 6,
          remindersEnabled: false,
        },
      );
      assertEquals(legacyUpdate.version, 2);

      const canonicalRead = await personStore.getOwnerProfile(
        canonical.appUserId,
      );
      assertEquals(canonicalRead.enabled, true);
      assertEquals(canonicalRead.ownerUserId, canonical.appUserId);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanup(canonical);
      await cleanup(legacy);
      await sql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
