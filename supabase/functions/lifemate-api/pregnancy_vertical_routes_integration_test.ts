import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPregnancyCaptureRouteHandler } from "./pregnancy_capture.ts";
import { createPregnancyMeasurementRouteHandler } from "./pregnancy_measurements.ts";
import { createPregnancyRecordsRouteHandler } from "./pregnancy_records.ts";
import { createPregnancyTreatmentRouteHandler } from "./pregnancy_treatments.ts";
import { createPersonMedicationStore } from "./person_medications.ts";
import { createPersonTreatmentPlanStore } from "./person_treatment_plans.ts";
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
    const otherEpisodeId = crypto.randomUUID();

    const capture = createPregnancyCaptureRouteHandler(databaseUrl);
    const measurements = createPregnancyMeasurementRouteHandler(databaseUrl);
    const treatments = createPregnancyTreatmentRouteHandler(databaseUrl);
    const records = createPregnancyRecordsRouteHandler(databaseUrl);
    const medications = createPersonMedicationStore(databaseUrl);
    const treatmentPlans = createPersonTreatmentPlanStore(databaseUrl);

    const observedAtUtc = new Date(Date.now() - 60_000).toISOString();
    const localDate = observedAtUtc.slice(0, 10);
    const checkInRequestId = crypto.randomUUID();
    const symptomRequestId = crypto.randomUUID();
    const moodRequestId = crypto.randomUUID();
    const measurementRequestId = crypto.randomUUID();

    let observationId: string | null = null;
    let medicationId: string | null = null;
    let treatmentPlanId: string | null = null;

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

      await assertApiError(
        () =>
          capture({
            request: postRequest("/api/v1/cocoon/pregnancy/symptoms", {
              clientRequestId: crypto.randomUUID(),
              observedAtUtc,
              localDate,
              timeZone: "UTC",
              symptomCode: "free text symptom must be rejected",
              intensity: "mild",
              note: "must never persist",
            }),
            path: "/api/v1/cocoon/pregnancy/symptoms",
            appUserId,
          }),
        400,
        "invalid_symptomCode",
      );
      const symptomsAfterInvalid = await adminSql`
        select count(*)::int as count
        from pregnancy.symptom_reports
        where mother_person_id=${personId}::uuid
      `;
      assertEquals(Number(symptomsAfterInvalid[0].count), 0);

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

      await assertApiError(
        () =>
          capture({
            request: postRequest("/api/v1/cocoon/pregnancy/symptoms", {
              clientRequestId: symptomRequestId,
              observedAtUtc,
              localDate,
              timeZone: "UTC",
              symptomCode: "nausea.morning",
              intensity: "strong",
              note: "changed retry must conflict",
            }),
            path: "/api/v1/cocoon/pregnancy/symptoms",
            appUserId,
          }),
        409,
        "idempotency_key_reused",
      );
      const symptomsAfterConflict = await adminSql`
        select count(*)::int as count
        from pregnancy.symptom_reports
        where mother_person_id=${personId}::uuid
      `;
      assertEquals(Number(symptomsAfterConflict[0].count), 1);

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

      await assertApiError(
        () =>
          measurements({
            request: postRequest("/api/v1/cocoon/pregnancy/measurements", {
              clientRequestId: crypto.randomUUID(),
              observationType: "heart_rate",
              valuePrimary: 80,
              observedAtUtc,
              observedLocalDate: localDate,
              timeZone: "UTC",
            }),
            path: "/api/v1/cocoon/pregnancy/measurements",
            appUserId,
          }),
        400,
        "pregnancy_measurement_type_invalid",
      );
      const observationsAfterInvalid = await adminSql`
        select count(*)::int as count
        from lifemate.health_observations
        where person_id=${personId}::uuid
      `;
      assertEquals(Number(observationsAfterInvalid[0].count), 0);

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

      const medication = await medications.createMedication(appUserId, {
        name: "Pregnancy integration treatment",
        strengthText: "10 mg",
        form: "tablet",
        notes: "synthetic pregnancy route fixture",
      });
      medicationId = String(medication.id);
      const plan = await treatmentPlans.createTreatmentPlan(appUserId, {
        medicationId,
        doseText: "one tablet",
        instructions: "synthetic integration instruction",
        startDate: localDate,
        endDate: localDate,
        timeZone: "UTC",
        schedules: [{ dayOfWeek: "monday", localTime: "12:00" }],
      });
      treatmentPlanId = String(plan.id);

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
      const activePlans = treatmentBody.treatmentPlans as Array<
        Record<string, unknown>
      >;
      assertEquals(activePlans.length, 1);
      assertEquals(activePlans[0].id, treatmentPlanId);
      assertEquals(treatmentBody.doseOccurrences, []);

      const recordList = await records({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/records",
          {
            fromDate: localDate,
            toDate: localDate,
            categories: "check_ins,symptoms,moods,measurements,medications",
            limit: "30",
          },
        ),
        path: "/api/v1/cocoon/pregnancy/records",
        appUserId,
      });
      const recordBody = await recordList!.json() as Record<string, unknown>;
      assertEquals(recordBody.episodeId, episodeId);
      const recordItems = recordBody.items as Array<Record<string, unknown>>;
      assertEquals(recordItems.length, 5);
      assertEquals(
        new Set(recordItems.map((item) => String(item.sourceKind))),
        new Set([
          "pregnancy_check_in",
          "pregnancy_symptom",
          "pregnancy_mood",
          "health_observation",
          "treatment_plan",
        ]),
      );
      assertEquals(
        JSON.stringify(recordBody).includes("integration fixture"),
        false,
      );

      const baselineRecordPage = await records({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/records",
          {
            fromDate: localDate,
            toDate: localDate,
            categories: "symptoms,moods",
            limit: "30",
          },
        ),
        path: "/api/v1/cocoon/pregnancy/records",
        appUserId,
      });
      const baselineRecordBody = await baselineRecordPage!.json() as Record<
        string,
        unknown
      >;
      const baselineRecordItems = baselineRecordBody.items as Array<
        Record<string, unknown>
      >;
      assertEquals(baselineRecordItems.length, 2);

      const firstRecordPage = await records({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/records",
          {
            fromDate: localDate,
            toDate: localDate,
            categories: "symptoms,moods",
            limit: "1",
          },
        ),
        path: "/api/v1/cocoon/pregnancy/records",
        appUserId,
      });
      const firstRecordBody = await firstRecordPage!.json() as Record<
        string,
        unknown
      >;
      const firstRecordItems = firstRecordBody.items as Array<
        Record<string, unknown>
      >;
      assertEquals(firstRecordItems.length, 1);
      assertEquals(firstRecordItems[0].id, baselineRecordItems[0].id);
      const stableCursor = String(firstRecordBody.nextCursor ?? "");
      assertEquals(stableCursor.length > 0, true);

      const newerObservedAtUtc = new Date(Date.now() - 10_000).toISOString();
      const newerSymptom = await capture({
        request: postRequest("/api/v1/cocoon/pregnancy/symptoms", {
          clientRequestId: crypto.randomUUID(),
          observedAtUtc: newerObservedAtUtc,
          localDate,
          timeZone: "UTC",
          symptomCode: "fatigue",
          intensity: "mild",
          note: "newer private pagination note",
        }),
        path: "/api/v1/cocoon/pregnancy/symptoms",
        appUserId,
      });
      assertEquals(newerSymptom?.status, 201);

      const secondRecordPage = await records({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/records",
          {
            fromDate: localDate,
            toDate: localDate,
            categories: "symptoms,moods",
            limit: "1",
            cursor: stableCursor,
          },
        ),
        path: "/api/v1/cocoon/pregnancy/records",
        appUserId,
      });
      const secondRecordBody = await secondRecordPage!.json() as Record<
        string,
        unknown
      >;
      const secondRecordItems = secondRecordBody.items as Array<
        Record<string, unknown>
      >;
      assertEquals(secondRecordItems.length, 1);
      assertEquals(secondRecordItems[0].id, baselineRecordItems[1].id);
      assertEquals(secondRecordItems[0].id === firstRecordItems[0].id, false);
      assertEquals(
        JSON.stringify(secondRecordBody).includes("newer private pagination note"),
        false,
      );

      const refreshedFirstPage = await records({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/records",
          {
            fromDate: localDate,
            toDate: localDate,
            categories: "symptoms,moods",
            limit: "1",
          },
        ),
        path: "/api/v1/cocoon/pregnancy/records",
        appUserId,
      });
      const refreshedFirstBody = await refreshedFirstPage!.json() as Record<
        string,
        unknown
      >;
      assertEquals(
        (refreshedFirstBody.items as Array<Record<string, unknown>>)[0].id ===
          firstRecordItems[0].id,
        false,
      );

      await assertApiError(
        () =>
          records({
            request: getRequest(
              "/api/v1/cocoon/pregnancy/records",
              {
                fromDate: localDate,
                toDate: localDate,
                categories: "unknown",
              },
            ),
            path: "/api/v1/cocoon/pregnancy/records",
            appUserId,
          }),
        400,
        "pregnancy_records_category_invalid",
      );
      await assertApiError(
        () =>
          records({
            request: getRequest(
              "/api/v1/cocoon/pregnancy/records",
              {
                fromDate: localDate,
                toDate: localDate,
                limit: "101",
              },
            ),
            path: "/api/v1/cocoon/pregnancy/records",
            appUserId,
          }),
        400,
        "pregnancy_records_limit_invalid",
      );
      await assertApiError(
        () =>
          records({
            request: getRequest(
              "/api/v1/cocoon/pregnancy/records",
              {
                fromDate: localDate,
                toDate: localDate,
                cursor: "not-a-valid-records-cursor",
              },
            ),
            path: "/api/v1/cocoon/pregnancy/records",
            appUserId,
          }),
        400,
        "pregnancy_records_cursor_invalid",
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

      await adminSql`
        insert into pregnancy.episodes(
          id,mother_person_id,status,activated_at_utc,
          creation_idempotency_key_hash
        ) values (
          ${otherEpisodeId}::uuid,${otherPersonId}::uuid,'active',now(),
          ${crypto.randomUUID().replaceAll("-", "").repeat(2)}
        )
      `;

      const unrelatedMeasurements = await measurements({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/measurements",
          { fromDate: localDate, toDate: localDate },
        ),
        path: "/api/v1/cocoon/pregnancy/measurements",
        appUserId: otherAppUserId,
      });
      const unrelatedMeasurementBody = await unrelatedMeasurements!.json() as
        Record<string, unknown>;
      assertEquals(unrelatedMeasurementBody.episodeId, otherEpisodeId);
      assertEquals(
        (unrelatedMeasurementBody.items as Array<Record<string, unknown>>)
          .length,
        0,
      );

      const unrelatedTreatments = await treatments({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/treatments",
          { fromDate: localDate, toDate: localDate },
        ),
        path: "/api/v1/cocoon/pregnancy/treatments",
        appUserId: otherAppUserId,
      });
      const unrelatedTreatmentBody = await unrelatedTreatments!.json() as
        Record<string, unknown>;
      assertEquals(unrelatedTreatmentBody.episodeId, otherEpisodeId);
      assertEquals(
        (unrelatedTreatmentBody.treatmentPlans as Array<
          Record<string, unknown>
        >)
          .length,
        0,
      );
      assertEquals(
        (unrelatedTreatmentBody.doseOccurrences as Array<
          Record<string, unknown>
        >)
          .length,
        0,
      );

      const unrelatedRecords = await records({
        request: getRequest(
          "/api/v1/cocoon/pregnancy/records",
          {
            fromDate: localDate,
            toDate: localDate,
            categories: "measurements,medications",
          },
        ),
        path: "/api/v1/cocoon/pregnancy/records",
        appUserId: otherAppUserId,
      });
      const unrelatedRecordBody = await unrelatedRecords!.json() as Record<
        string,
        unknown
      >;
      assertEquals(unrelatedRecordBody.episodeId, otherEpisodeId);
      assertEquals(
        (unrelatedRecordBody.items as Array<Record<string, unknown>>).length,
        0,
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
      if (treatmentPlanId) {
        await adminSql`
          delete from lifemate.treatment_schedules
          where treatment_plan_id=${treatmentPlanId}::uuid
        `.catch(() => undefined);
        await adminSql`
          delete from lifemate.audit_logs
          where resource_type='treatment_plan'
            and resource_id=${treatmentPlanId}::uuid
        `.catch(() => undefined);
        await adminSql`
          delete from lifemate.treatment_plans
          where id=${treatmentPlanId}::uuid
        `.catch(() => undefined);
      }
      if (medicationId) {
        await adminSql`
          delete from lifemate.audit_logs
          where resource_type='medication'
            and resource_id=${medicationId}::uuid
        `.catch(() => undefined);
        await adminSql`
          delete from lifemate.medications
          where id=${medicationId}::uuid
        `.catch(() => undefined);
      }
      await cleanupIdentity(appUserId, accountId, personId);
      await cleanupIdentity(otherAppUserId, otherAccountId, otherPersonId);
    }
  },
});

Deno.test({
  name:
    "pregnancy canonical persistence denies mobile roles and remains available to the restricted edge runtime",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const rows = await adminSql`
      with target(schema_name,table_name) as (
        values
          ('pregnancy','episodes'),
          ('pregnancy','dating_revisions'),
          ('pregnancy','episode_events'),
          ('pregnancy','daily_check_ins'),
          ('pregnancy','symptom_reports'),
          ('pregnancy','mood_entries'),
          ('pregnancy','care_event_links'),
          ('pregnancy','observation_links'),
          ('lifemate','care_events'),
          ('lifemate','health_observations'),
          ('lifemate','medications'),
          ('lifemate','treatment_plans'),
          ('lifemate','treatment_schedules')
      )
      select schema_name,table_name,
        has_table_privilege(
          'authenticated',
          format('%I.%I',schema_name,table_name),
          'select'
        ) as authenticated_select,
        has_table_privilege(
          'anon',
          format('%I.%I',schema_name,table_name),
          'select'
        ) as anon_select,
        has_table_privilege(
          'lifemate_edge_runtime',
          format('%I.%I',schema_name,table_name),
          'select,insert,update,delete'
        ) as runtime_crud
      from target
      order by schema_name,table_name
    `;
    assertEquals(rows.length, 13);
    for (const row of rows) {
      const label = `${row.schema_name}.${row.table_name}`;
      assertEquals(row.authenticated_select, false, label);
      assertEquals(row.anon_select, false, label);
      assertEquals(row.runtime_crud, true, label);
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
