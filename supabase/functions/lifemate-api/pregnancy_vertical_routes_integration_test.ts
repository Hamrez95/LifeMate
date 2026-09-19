import {
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPregnancyCaptureRouteHandler } from "./pregnancy_capture.ts";
import { createPregnancyMeasurementRouteHandler } from "./pregnancy_measurements.ts";
import { createPregnancyRecordsRouteHandler } from "./pregnancy_records.ts";
import { createPregnancyTreatmentRouteHandler } from "./pregnancy_treatments.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for pregnancy vertical integration tests.",
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
    "pregnancy daily capture measurements treatments and records stay Person-isolated on real PostgreSQL",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const otherAppUserId = crypto.randomUUID();
    const otherAccountId = crypto.randomUUID();
    const otherPersonId = crypto.randomUUID();
    const episodeId = crypto.randomUUID();

    const capture = createPregnancyCaptureRouteHandler(databaseUrl);
    const measurements = createPregnancyMeasurementRouteHandler(databaseUrl);
    const treatments = createPregnancyTreatmentRouteHandler(databaseUrl);
    const records = createPregnancyRecordsRouteHandler(databaseUrl);

    const observedAtUtc = new Date(Date.now() - 60_000).toISOString();
    const localDate = observedAtUtc.slice(0, 10);
    const checkInRequestId = crypto.randomUUID();
    const symptomRequestId = crypto.randomUUID();
    const moodRequestId = crypto.randomUUID();
    const measurementRequestId = crypto.randomUUID();

    let observationId: string | null = null;

    try {
      await seedIdentity(
        appUserId,
        accountId,
        personId,
        `pregnancy-vertical-owner-${crypto.randomUUID()}`,
      );
      await seedIdentity(
        otherAppUserId,
        otherAccountId,
        otherPersonId,
        `pregnancy-vertical-other-${crypto.randomUUID()}`,
      );
      await adminSql`
        insert into pregnancy.episodes(
          id,mother_person_id,status,activated_at_utc,
          creation_idempotency_key_hash
        ) values (
          ${episodeId}::uuid,${personId}::uuid,'active',now(),
          ${crypto.randomUUID().replaceAll("-", "").repeat(2)}
        )
      `;

      const checkInBody = {
        clientRequestId: checkInRequestId,
        observedAtUtc,
        localDate,
        timeZone: "UTC",
        feeling: "comfortable",
        energy: "steady",
      };
      const firstCheckIn = await capture({
        request: postRequest("/api/v1/cocoon/pregnancy/check-ins", checkInBody),
        path: "/api/v1/cocoon/pregnancy/check-ins",
        appUserId,
      });
      assertEquals(firstCheckIn?.status, 201);
      const firstCheckInBody = await firstCheckIn!.json() as Record<
        string,
        unknown
      >;
      const firstCheckInRow = firstCheckInBody.checkIn as Record<
        string,
        unknown
      >;

      const replayCheckIn = await capture({
        request: postRequest("/api/v1/cocoon/pregnancy/check-ins", checkInBody),
        path: "/api/v1/cocoon/pregnancy/check-ins",
        appUserId,
      });
      const replayCheckInBody = await replayCheckIn!.json() as Record<
        string,
        unknown
      >;
      assertEquals(
        (replayCheckInBody.checkIn as Record<string, unknown>).id,
        firstCheckInRow.id,
      );

      await assertApiError(
        () =>
          capture({
            request: postRequest("/api/v1/cocoon/pregnancy/check-ins", {
              ...checkInBody,
              clientRequestId: crypto.randomUUID(),
            }),
            path: "/api/v1/cocoon/pregnancy/check-ins",
            appUserId,
          }),
        409,
        "daily_check_in_exists",
      );

      const symptom = await capture({
        request: postRequest("/api/v1/cocoon/pregnancy/symptoms", {
          clientRequestId: symptomRequestId,
          observedAtUtc,
          localDate,
          timeZone: "UTC",
          symptomCode: "nausea.morning",
          intensity: "mild",
          note: "integration fixture",
        }),
        path: "/api/v1/cocoon/pregnancy/symptoms",
        appUserId,
      });
      assertEquals(symptom?.status, 201);

      const mood = await capture({
        request: postRequest("/api/v1/cocoon/pregnancy/moods", {
          clientRequestId: moodRequestId,
          observedAtUtc,
          localDate,
          timeZone: "UTC",
          moodCode: "good",
        }),
        path: "/api/v1/cocoon/pregnancy/moods",
        appUserId,
      });
      assertEquals(mood?.status, 201);

      const measurement = await measurements({
        request: postRequest("/api/v1/cocoon/pregnancy/measurements", {
          clientRequestId: measurementRequestId,
          observationType: "weight",
          valuePrimary: 70.5,
          observedAtUtc,
          observedLocalDate: localDate,
          timeZone: "UTC",
        }),
        path: "/api/v1/cocoon/pregnancy/measurements",
        appUserId,
      });
      assertEquals(measurement?.status, 201);
      const measurementBody = await measurement!.json() as Record<
        string,
        unknown
      >;
      const observation = measurementBody.observation as Record<
        string,
        unknown
      >;
      observationId = String(observation.id);
      assertEquals(observation.personId, personId);
      assertEquals(observation.sourceApplicationCode, "cocoonmate");

      const measurementReplay = await measurements({
        request: postRequest("/api/v1/cocoon/pregnancy/measurements", {
          clientRequestId: measurementRequestId,
          observationType: "weight",
          valuePrimary: 70.5,
          observedAtUtc,
          observedLocalDate: localDate,
          timeZone: "UTC",
        }),
        path: "/api/v1/cocoon/pregnancy/measurements",
        appUserId,
      });
      const measurementReplayBody = await measurementReplay!.json() as Record<
        string,
        unknown
      >;
      assertEquals(
        (measurementReplayBody.observation as Record<string, unknown>).id,
        observationId,
      );

      const daily = await capture({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/daily-captures",
          { fromDate: localDate, toDate: localDate },
        ),
        path: "/api/v1/cocoon/pregnancy/daily-captures",
        appUserId,
      });
      const dailyBody = await daily!.json() as Record<string, unknown>;
      assertEquals((dailyBody.checkIns as unknown[]).length, 1);
      assertEquals((dailyBody.symptoms as unknown[]).length, 1);
      assertEquals((dailyBody.moods as unknown[]).length, 1);

      const measurementList = await measurements({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/measurements",
          { fromDate: localDate, toDate: localDate },
        ),
        path: "/api/v1/cocoon/pregnancy/measurements",
        appUserId,
      });
      const measurementListBody = await measurementList!.json() as Record<
        string,
        unknown
      >;
      assertEquals(measurementListBody.episodeId, episodeId);
      assertEquals((measurementListBody.items as unknown[]).length, 1);

      const treatmentList = await treatments({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/treatments",
          { fromDate: localDate, toDate: localDate },
        ),
        path: "/api/v1/cocoon/pregnancy/treatments",
        appUserId,
      });
      const treatmentBody = await treatmentList!.json() as Record<
        string,
        unknown
      >;
      assertEquals(treatmentBody.episodeId, episodeId);
      assertEquals(treatmentBody.treatmentPlans, []);
      assertEquals(treatmentBody.doseOccurrences, []);

      const recordList = await records({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/records",
          {
            fromDate: localDate,
            toDate: localDate,
            categories: "check_ins,symptoms,moods,measurements",
            limit: "30",
          },
        ),
        path: "/api/v1/cocoon/pregnancy/records",
        appUserId,
      });
      const recordBody = await recordList!.json() as Record<string, unknown>;
      assertEquals(recordBody.episodeId, episodeId);
      const recordItems = recordBody.items as Array<Record<string, unknown>>;
      assertEquals(recordItems.length, 4);
      assertEquals(
        new Set(recordItems.map((item) => String(item.sourceKind))),
        new Set([
          "pregnancy_check_in",
          "pregnancy_symptom",
          "pregnancy_mood",
          "health_observation",
        ]),
      );

      await assertApiError(
        () =>
          records({
            request: getRequest(
              "/api/v1/cocoon/pregnancy/records",
              { fromDate: localDate, toDate: localDate },
            ),
            path: "/api/v1/cocoon/pregnancy/records",
            appUserId: otherAppUserId,
          }),
        409,
        "active_pregnancy_required",
      );

      const persisted = await adminSql`
        select
          (select count(*)::int from pregnancy.daily_check_ins
            where mother_person_id=${personId}::uuid) as check_ins,
          (select count(*)::int from pregnancy.symptom_reports
            where mother_person_id=${personId}::uuid) as symptoms,
          (select count(*)::int from pregnancy.mood_entries
            where mother_person_id=${personId}::uuid) as moods,
          (select count(*)::int from pregnancy.observation_links
            where episode_id=${episodeId}::uuid) as measurement_links,
          (select count(*)::int from lifemate.health_observations
            where person_id=${otherPersonId}::uuid) as unrelated_observations
      `;
      assertEquals(Number(persisted[0].check_ins), 1);
      assertEquals(Number(persisted[0].symptoms), 1);
      assertEquals(Number(persisted[0].moods), 1);
      assertEquals(Number(persisted[0].measurement_links), 1);
      assertEquals(Number(persisted[0].unrelated_observations), 0);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await adminSql`
        delete from pregnancy.episodes
        where mother_person_id in (${personId}::uuid,${otherPersonId}::uuid)
      `.catch(() => undefined);
      if (observationId) {
        await adminSql`
          delete from lifemate.audit_logs
          where resource_type='health_observation'
            and resource_id=${observationId}::uuid
        `.catch(() => undefined);
        await adminSql`
          delete from lifemate.health_observations
          where id=${observationId}::uuid
        `.catch(() => undefined);
      }
      await cleanupIdentity(appUserId, accountId, personId);
      await cleanupIdentity(otherAppUserId, otherAccountId, otherPersonId);
    }
  },
});

Deno.test({
  name:
    "pregnancy vertical tables deny mobile roles and remain available to the restricted edge runtime",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const rows = await adminSql`
      select table_name,
        has_table_privilege(
          'authenticated',
          'pregnancy.' || table_name,
          'select'
        ) as authenticated_select,
        has_table_privilege(
          'anon',
          'pregnancy.' || table_name,
          'select'
        ) as anon_select,
        has_table_privilege(
          'lifemate_edge_runtime',
          'pregnancy.' || table_name,
          'select,insert,update,delete'
        ) as runtime_crud
      from unnest(array[
        'daily_check_ins',
        'symptom_reports',
        'mood_entries',
        'care_event_links',
        'observation_links'
      ]) as tables(table_name)
      order by table_name
    `;
    assertEquals(rows.length, 5);
    for (const row of rows) {
      assertEquals(row.authenticated_select, false, String(row.table_name));
      assertEquals(row.anon_select, false, String(row.table_name));
      assertEquals(row.runtime_crud, true, String(row.table_name));
    }
  },
});

function postRequest(
  path: string,
  body: Record<string, unknown>,
): Request {
  return new Request(`https://lifemate.test${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function getRequest(
  path: string,
  query: Record<string, string>,
): Request {
  const url = new URL(`https://lifemate.test${path}`);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }
  return new Request(url);
}

async function seedIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
  authSubject: string,
): Promise<void> {
  await adminSql`
    insert into lifemate.app_users(
      id,auth_subject,status,created_at_utc,updated_at_utc
    ) values (
      ${appUserId}::uuid,${authSubject},'Active',now(),now()
    )
  `;
  await adminSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${appUserId}::uuid
  `;
  await adminSql`
    insert into identity.accounts(
      id,legacy_app_user_id,status,created_at_utc,updated_at_utc
    ) values (
      ${accountId}::uuid,${appUserId}::uuid,'Active',now(),now()
    )
  `;
  await adminSql`
    insert into core.persons(id,status,subject_category)
    values(${personId}::uuid,'Active','Adult')
  `;
  await adminSql`
    insert into core.account_person_links(
      account_id,person_id,link_type,status,created_at_utc
    ) values (
      ${accountId}::uuid,${personId}::uuid,'Self','Active',now()
    )
  `;
}

async function cleanupIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
): Promise<void> {
  await adminSql`
    delete from commerce.entitlements
    where grantee_account_id in (${appUserId}::uuid,${accountId}::uuid)
       or beneficiary_person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from ecosystem.app_enrollments
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from identity.external_identities
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.account_person_links
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
       or person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.person_profiles
    where person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.persons
    where id in (${appUserId}::uuid,${personId}::uuid)
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
}

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  const error = await assertRejects(action, ApiError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
}
