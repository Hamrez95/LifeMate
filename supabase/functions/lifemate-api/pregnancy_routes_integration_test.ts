import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPregnancyRouteHandler } from "./pregnancy_routes.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for pregnancy route integration tests.",
  );
}

const adminSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name:
    "pregnancy route resolves remapped Account and Person, audits canonical actor, and replays activation idempotently",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = `pregnancy-route-${crypto.randomUUID()}`;
    const idempotencyKey = `pregnancy-route-${crypto.randomUUID()}`;
    const handler = createPregnancyRouteHandler(databaseUrl);

    try {
      await seedRemappedIdentity({ appUserId, accountId, personId, authSubject });

      const first = await handler({
        request: createRequest(idempotencyKey),
        path: "/api/v1/cocoon/pregnancy/episodes",
        appUserId,
      });
      assertEquals(first?.status, 201);
      const firstBody = await first!.json() as Record<string, unknown>;
      const firstEpisode = firstBody.episode as Record<string, unknown>;
      assertEquals(firstEpisode.motherPersonId, personId);
      assertEquals(firstEpisode.status, "active");
      const dating = firstEpisode.dating as Record<string, unknown>;
      assertEquals(dating.gestationalAge, {
        totalDays: 38,
        week: 5,
        day: 3,
        basis: "lmp",
      });
      const episodeId = String(firstEpisode.id);

      const replay = await handler({
        request: createRequest(idempotencyKey),
        path: "/api/v1/cocoon/pregnancy/episodes",
        appUserId,
      });
      assertEquals(replay?.status, 201);
      const replayBody = await replay!.json() as Record<string, unknown>;
      const replayEpisode = replayBody.episode as Record<string, unknown>;
      assertEquals(replayEpisode.id, episodeId);

      const persisted = await adminSql`
        select
          (select count(*)::int
           from pregnancy.episodes
           where mother_person_id=${personId}::uuid) as episode_count,
          (select count(*)::int
           from pregnancy.episodes
           where mother_person_id=${appUserId}::uuid) as legacy_episode_count,
          (select count(*)::int
           from pregnancy.episode_events
           where episode_id=${episodeId}::uuid
             and actor_account_id=${accountId}::uuid) as canonical_actor_events,
          (select count(*)::int
           from pregnancy.episode_events
           where episode_id=${episodeId}::uuid
             and actor_account_id=${appUserId}::uuid) as legacy_actor_events
      `;
      assertEquals(Number(persisted[0].episode_count), 1);
      assertEquals(Number(persisted[0].legacy_episode_count), 0);
      assertEquals(Number(persisted[0].canonical_actor_events), 1);
      assertEquals(Number(persisted[0].legacy_actor_events), 0);
    } finally {
      await adminSql`
        delete from pregnancy.episodes where mother_person_id=${personId}::uuid
      `.catch(() => undefined);
      await cleanupRemappedIdentity({ appUserId, accountId, personId });
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await adminSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

function createRequest(idempotencyKey: string): Request {
  return new Request(
    "https://lifemate.test/api/v1/cocoon/pregnancy/episodes?asOfDate=2026-09-08",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": idempotencyKey,
      },
      body: JSON.stringify({
        status: "active",
        method: "lmp",
        lmpDate: "2026-08-01",
      }),
    },
  );
}

async function seedRemappedIdentity(input: {
  appUserId: string;
  accountId: string;
  personId: string;
  authSubject: string;
}): Promise<void> {
  await adminSql`
    insert into lifemate.app_users(
      id,auth_subject,status,created_at_utc,updated_at_utc
    ) values(
      ${input.appUserId}::uuid,${input.authSubject},'Active',now(),now()
    )
  `;
  await adminSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${input.appUserId}::uuid
  `;
  await adminSql`
    insert into identity.accounts(
      id,legacy_app_user_id,status,created_at_utc,updated_at_utc
    ) values(
      ${input.accountId}::uuid,${input.appUserId}::uuid,'Active',now(),now()
    )
  `;
  await adminSql`
    insert into core.persons(id,status,subject_category)
    values(${input.personId}::uuid,'Active','Adult')
  `;
  await adminSql`
    insert into core.account_person_links(
      account_id,person_id,link_type,status,created_at_utc
    ) values(
      ${input.accountId}::uuid,${input.personId}::uuid,'Self','Active',now()
    )
  `;
}

async function cleanupRemappedIdentity(input: {
  appUserId: string;
  accountId: string;
  personId: string;
}): Promise<void> {
  await adminSql`
    delete from commerce.entitlements
    where grantee_account_id in (${input.appUserId}::uuid,${input.accountId}::uuid)
       or beneficiary_person_id in (${input.appUserId}::uuid,${input.personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from ecosystem.app_enrollments
    where account_id in (${input.appUserId}::uuid,${input.accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from identity.external_identities
    where account_id in (${input.appUserId}::uuid,${input.accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.account_person_links
    where account_id in (${input.appUserId}::uuid,${input.accountId}::uuid)
       or person_id in (${input.appUserId}::uuid,${input.personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.person_profiles
    where person_id in (${input.appUserId}::uuid,${input.personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.persons
    where id in (${input.appUserId}::uuid,${input.personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${input.appUserId}::uuid,${input.accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from identity.accounts
    where id in (${input.appUserId}::uuid,${input.accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from lifemate.app_users where id=${input.appUserId}::uuid
  `.catch(() => undefined);
}
