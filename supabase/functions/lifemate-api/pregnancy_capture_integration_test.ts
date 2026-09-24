import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPregnancyCaptureRouteHandler } from "./pregnancy_capture.ts";
import { createPregnancyRouteHandler } from "./pregnancy_routes.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for pregnancy capture integration tests.",
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
    "pregnancy capture clientRequestId rejects changed semantics across durable replay identity",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = `pregnancy-capture-${crypto.randomUUID()}`;
    const pregnancyIdempotencyKey = `pregnancy-capture-${crypto.randomUUID()}`;
    const symptomCatalogVersion = `test-${crypto.randomUUID()}`;
    const symptomCatalogReleaseId = crypto.randomUUID();
    const checkInRequestId = crypto.randomUUID();
    const symptomRequestId = crypto.randomUUID();
    const moodRequestId = crypto.randomUUID();
    const pregnancyHandler = createPregnancyRouteHandler(databaseUrl);
    const captureHandler = createPregnancyCaptureRouteHandler(databaseUrl);

    try {
      await seedRemappedIdentity({
        appUserId,
        accountId,
        personId,
        authSubject,
      });
      await adminSql`
        insert into pregnancy.symptom_catalog_releases(
          id,version,status,reviewed_by,reviewed_at_utc,published_at_utc
        ) values(
          ${symptomCatalogReleaseId}::uuid,
          ${symptomCatalogVersion},
          'published',
          'automated integration test fixture',
          now(),
          now()
        )
      `;
      await adminSql`
        insert into pregnancy.symptom_catalog_entries(
          release_id,locale,code,display_label,sort_order
        ) values(
          ${symptomCatalogReleaseId}::uuid,'en','test.symptom',
          'Synthetic test symptom',0
        )
      `;

      const pregnancyResponse = await pregnancyHandler({
        request: new Request(
          "https://lifemate.test/api/v1/cocoon/pregnancy/episodes?asOfDate=2026-09-19",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Idempotency-Key": pregnancyIdempotencyKey,
            },
            body: JSON.stringify({
              status: "active",
              method: "lmp",
              lmpDate: "2026-08-01",
            }),
          },
        ),
        path: "/api/v1/cocoon/pregnancy/episodes",
        appUserId,
      });
      assertEquals(pregnancyResponse?.status, 201);

      const firstCheckIn = await submitCapture({
        handler: captureHandler,
        path: "/api/v1/cocoon/pregnancy/check-ins",
        appUserId,
        body: {
          clientRequestId: checkInRequestId,
          observedAtUtc: "2026-09-19T10:00:00.000Z",
          localDate: "2026-09-19",
          timeZone: "Asia/Tehran",
          feeling: "comfortable",
          energy: "steady",
        },
      });
      assertEquals(firstCheckIn?.status, 201);
      const checkInConflict = await assertRejects(
        () =>
          submitCapture({
            handler: captureHandler,
            path: "/api/v1/cocoon/pregnancy/check-ins",
            appUserId,
            body: {
              clientRequestId: checkInRequestId,
              observedAtUtc: "2026-09-19T10:00:00.000Z",
              localDate: "2026-09-19",
              timeZone: "Asia/Tehran",
              feeling: "comfortable",
              energy: "high",
            },
          }),
        ApiError,
      );
      assertEquals(checkInConflict.status, 409);
      assertEquals(checkInConflict.code, "idempotency_key_reused");

      const firstSymptom = await submitCapture({
        handler: captureHandler,
        path: "/api/v1/cocoon/pregnancy/symptoms",
        appUserId,
        body: {
          clientRequestId: symptomRequestId,
          observedAtUtc: "2026-09-19T10:15:00.000Z",
          localDate: "2026-09-19",
          timeZone: "Asia/Tehran",
          symptomCode: "test.symptom",
          catalogVersion: symptomCatalogVersion,
          intensity: "mild",
          note: "first private note",
        },
      });
      assertEquals(firstSymptom?.status, 201);
      const symptomConflict = await assertRejects(
        () =>
          submitCapture({
            handler: captureHandler,
            path: "/api/v1/cocoon/pregnancy/symptoms",
            appUserId,
            body: {
              clientRequestId: symptomRequestId,
              observedAtUtc: "2026-09-19T10:15:00.000Z",
              localDate: "2026-09-19",
              timeZone: "Asia/Tehran",
              symptomCode: "test.symptom",
              catalogVersion: symptomCatalogVersion,
              intensity: "mild",
              note: "changed private note",
            },
          }),
        ApiError,
      );
      assertEquals(symptomConflict.status, 409);
      assertEquals(symptomConflict.code, "idempotency_key_reused");

      const firstMood = await submitCapture({
        handler: captureHandler,
        path: "/api/v1/cocoon/pregnancy/moods",
        appUserId,
        body: {
          clientRequestId: moodRequestId,
          observedAtUtc: "2026-09-19T10:30:00.000Z",
          localDate: "2026-09-19",
          timeZone: "Asia/Tehran",
          moodCode: "good",
        },
      });
      assertEquals(firstMood?.status, 201);
      const moodConflict = await assertRejects(
        () =>
          submitCapture({
            handler: captureHandler,
            path: "/api/v1/cocoon/pregnancy/moods",
            appUserId,
            body: {
              clientRequestId: moodRequestId,
              observedAtUtc: "2026-09-19T10:31:00.000Z",
              localDate: "2026-09-19",
              timeZone: "Asia/Tehran",
              moodCode: "good",
            },
          }),
        ApiError,
      );
      assertEquals(moodConflict.status, 409);
      assertEquals(moodConflict.code, "idempotency_key_reused");

      const rows = await adminSql`
        select
          (select count(*)::int from pregnancy.daily_check_ins
           where mother_person_id=${personId}::uuid
             and client_request_id=${checkInRequestId}::uuid) as check_in_count,
          (select count(*)::int from pregnancy.symptom_reports
           where mother_person_id=${personId}::uuid
             and client_request_id=${symptomRequestId}::uuid) as symptom_count,
          (select count(*)::int from pregnancy.mood_entries
           where mother_person_id=${personId}::uuid
             and client_request_id=${moodRequestId}::uuid) as mood_count
      `;
      assertEquals(Number(rows[0].check_in_count), 1);
      assertEquals(Number(rows[0].symptom_count), 1);
      assertEquals(Number(rows[0].mood_count), 1);
    } finally {
      await adminSql`
        delete from pregnancy.symptom_catalog_entries
        where release_id=${symptomCatalogReleaseId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from pregnancy.symptom_catalog_releases
        where id=${symptomCatalogReleaseId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from pregnancy.daily_check_ins
        where mother_person_id=${personId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from pregnancy.symptom_reports
        where mother_person_id=${personId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from pregnancy.mood_entries
        where mother_person_id=${personId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from pregnancy.dating_revisions
        where episode_id in (
          select id from pregnancy.episodes
          where mother_person_id=${personId}::uuid
        )
      `.catch(() => undefined);
      await adminSql`
        delete from pregnancy.episode_events
        where episode_id in (
          select id from pregnancy.episodes
          where mother_person_id=${personId}::uuid
        )
      `.catch(() => undefined);
      await adminSql`
        delete from pregnancy.episodes
        where mother_person_id=${personId}::uuid
      `.catch(() => undefined);
      await cleanupRemappedIdentity({ appUserId, accountId, personId });
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await adminSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

async function submitCapture(input: {
  handler: ReturnType<typeof createPregnancyCaptureRouteHandler>;
  path: string;
  appUserId: string;
  body: Record<string, unknown>;
}): Promise<Response | null> {
  return await input.handler({
    request: new Request(`https://lifemate.test${input.path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input.body),
    }),
    path: input.path,
    appUserId: input.appUserId,
  });
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
