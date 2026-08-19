import {
  assertEquals,
  assertNotEquals,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPersonWomenCalendarStore } from "./person_women_calendar.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Women Calendar owner retirement tests.",
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

function day(offset: number): string {
  const value = new Date();
  value.setUTCHours(0, 0, 0, 0);
  value.setUTCDate(value.getUTCDate() + offset);
  return value.toISOString().slice(0, 10);
}

Deno.test({
  name:
    "canonical Women Calendar episode/daily rows omit AppUser while legacy inserts still map Person",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const identity = await createUnequalIdentity();
    const women = createPersonWomenCalendarStore(databaseUrl);
    const canonicalEpisodeDate = day(-28);
    const canonicalDailyDate = day(0);
    const legacyEpisodeDate = day(-56);
    const legacyDailyDate = day(-2);
    const legacyEpisodeId = crypto.randomUUID();
    const legacyDailyId = crypto.randomUUID();

    try {
      const schemaRows = await sql`
        select table_name,column_name,is_nullable
        from information_schema.columns
        where table_schema='lifemate'
          and table_name in (
            'women_calendar_episodes','women_calendar_daily_logs'
          )
          and column_name in ('owner_user_id','owner_person_id')
        order by table_name,column_name
      `;
      assertEquals(
        schemaRows.map((row) => ({
          table: String(row.table_name),
          column: String(row.column_name),
          nullable: String(row.is_nullable),
        })),
        [
          {
            table: "women_calendar_daily_logs",
            column: "owner_person_id",
            nullable: "NO",
          },
          {
            table: "women_calendar_daily_logs",
            column: "owner_user_id",
            nullable: "YES",
          },
          {
            table: "women_calendar_episodes",
            column: "owner_person_id",
            nullable: "NO",
          },
          {
            table: "women_calendar_episodes",
            column: "owner_user_id",
            nullable: "YES",
          },
        ],
      );

      const personUniqueIndexes = await sql`
        select indexname
        from pg_indexes
        where schemaname='lifemate'
          and indexname in (
            'uq_women_calendar_episode_person_start',
            'uq_women_calendar_daily_person_log'
          )
        order by indexname
      `;
      assertEquals(
        personUniqueIndexes.map((row) => String(row.indexname)),
        [
          "uq_women_calendar_daily_person_log",
          "uq_women_calendar_episode_person_start",
        ],
      );

      await women.updateOwnerProfile(identity.appUserId, {
        version: 0,
        enabled: true,
        lastPeriodStart: canonicalEpisodeDate,
        cycleLength: 28,
        periodLength: 5,
        remindersEnabled: true,
      });
      const canonicalEpisode = await women.createOwnerEpisode(
        identity.appUserId,
        {
          startedOn: canonicalEpisodeDate,
          endedOn: day(-24),
          privateNotes: "canonical episode",
        },
      );
      const canonicalDaily = await women.upsertOwnerDailyLog(
        identity.appUserId,
        {
          version: 0,
          loggedOn: canonicalDailyDate,
          mood: "good",
          energyLevel: 4,
          painLevel: 1,
          symptoms: ["fatigue"],
          privateNotes: "canonical daily",
          shareSummaryWithCompanion: false,
        },
      );

      const canonicalEpisodeRow = await sql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.women_calendar_episodes
        where id=${String(canonicalEpisode.id)}::uuid
      `;
      assertEquals(canonicalEpisodeRow[0]?.owner_user_id, null);
      assertEquals(canonicalEpisodeRow[0]?.owner_person_id, identity.personId);

      const canonicalDailyRow = await sql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.women_calendar_daily_logs
        where id=${String(canonicalDaily.id)}::uuid
      `;
      assertEquals(canonicalDailyRow[0]?.owner_user_id, null);
      assertEquals(canonicalDailyRow[0]?.owner_person_id, identity.personId);

      // Old-style compatibility writer: owner_user_id only. The retirement
      // trigger runs first and leaves it intact because Person is absent; the
      // existing sync trigger then resolves the explicit Self Person mapping.
      await sql`
        insert into lifemate.women_calendar_episodes(
          id,owner_user_id,started_on,ended_on,private_notes,
          version,created_at_utc,updated_at_utc
        ) values(
          ${legacyEpisodeId}::uuid,${identity.appUserId}::uuid,
          ${legacyEpisodeDate}::date,${day(-52)}::date,'legacy episode',
          1,now(),now()
        )
      `;
      await sql`
        insert into lifemate.women_calendar_daily_logs(
          id,owner_user_id,logged_on,mood,energy_level,pain_level,
          symptoms,private_notes,share_summary_with_companion,
          version,created_at_utc,updated_at_utc
        ) values(
          ${legacyDailyId}::uuid,${identity.appUserId}::uuid,
          ${legacyDailyDate}::date,'Good',3,1,
          array['Fatigue']::character varying[],'legacy daily',false,
          1,now(),now()
        )
      `;

      const legacyEpisode = await sql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.women_calendar_episodes
        where id=${legacyEpisodeId}::uuid
      `;
      assertEquals(legacyEpisode[0]?.owner_user_id, identity.appUserId);
      assertEquals(legacyEpisode[0]?.owner_person_id, identity.personId);

      const legacyDaily = await sql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.women_calendar_daily_logs
        where id=${legacyDailyId}::uuid
      `;
      assertEquals(legacyDaily[0]?.owner_user_id, identity.appUserId);
      assertEquals(legacyDaily[0]?.owner_person_id, identity.personId);

      // Retirement is INSERT-only: updating a historical compatibility row must
      // never erase its legacy identifier as an unintended migration side effect.
      await sql`
        update lifemate.women_calendar_daily_logs
        set private_notes='legacy daily updated',updated_at_utc=now()
        where id=${legacyDailyId}::uuid
      `;
      const legacyDailyAfterUpdate = await sql`
        select owner_user_id::text,owner_person_id::text
        from lifemate.women_calendar_daily_logs
        where id=${legacyDailyId}::uuid
      `;
      assertEquals(
        legacyDailyAfterUpdate[0]?.owner_user_id,
        identity.appUserId,
      );
      assertEquals(
        legacyDailyAfterUpdate[0]?.owner_person_id,
        identity.personId,
      );

      const listedEpisodes = await women.listOwnerEpisodes(identity.appUserId);
      assertEquals(listedEpisodes.length >= 2, true);
      const listedDaily = await women.listOwnerDailyLogs(
        identity.appUserId,
        day(-7),
        day(1),
      );
      assertEquals(listedDaily.length >= 2, true);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanup(identity);
      await sql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
