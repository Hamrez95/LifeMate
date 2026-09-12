import {
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createMutationIdempotencyStore } from "./idempotency.ts";
import { createPersonTreatmentCreateStore } from "./person_treatment_create.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for atomic treatment concurrency tests.",
  );
}

const fixtureSql = postgres(databaseUrl, {
  max: 4,
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

async function cleanupFixture(
  appUserId: string,
  accountId: string,
  personId: string,
  idempotencyKeys: string[] = [],
): Promise<void> {
  for (const key of idempotencyKeys) {
    await fixtureSql`
      delete from lifemate.idempotency_keys
      where operation='POST /api/v1/treatment-plans'
        and idempotency_key=${key}
    `.catch(() => undefined);
  }
  await fixtureSql`
    delete from lifemate.treatment_schedules
    where treatment_plan_id in (
      select id from lifemate.treatment_plans
      where patient_person_id=${personId}::uuid
    )
  `.catch(() => undefined);
  await fixtureSql`
    delete from lifemate.audit_logs
    where actor_user_id=${appUserId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    delete from lifemate.treatment_plans
    where patient_person_id=${personId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    delete from lifemate.medications
    where owner_person_id=${personId}::uuid
  `.catch(() => undefined);
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

function treatmentBody(
  medicationName: string,
  doseText = "one tablet",
): Record<string, unknown> {
  return {
    medication: {
      name: medicationName,
      strengthText: "10 mg",
      form: "tablet",
      notes: "synthetic concurrency fixture",
    },
    doseText,
    instructions: "synthetic concurrency fixture",
    startDate: "2030-03-01",
    endDate: "2030-03-01",
    timeZone: "Asia/Tehran",
    schedules: [{ dayOfWeek: "friday", localTime: "09:00" }],
    recurrence: { version: 2, enabled: false },
  };
}

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<ApiError> {
  const error = await assertRejects(action, ApiError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
  return error;
}

Deno.test({
  name:
    "concurrent atomic treatment creates reuse one canonical medication without collapsing distinct plans",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const store = createPersonTreatmentCreateStore(databaseUrl);
    const medicationName = `concurrent-reuse-${crypto.randomUUID()}`;

    try {
      await replaceBootstrapIdentity(
        appUserId,
        accountId,
        personId,
        authSubject,
      );

      const [first, second] = await Promise.all([
        store.createTreatment(appUserId, treatmentBody(medicationName, "one tablet")),
        store.createTreatment(appUserId, treatmentBody(medicationName, "half tablet")),
      ]);

      assertEquals(String(first.id) === String(second.id), false);
      assertEquals(
        String((first.medication as Record<string, unknown>).id),
        String((second.medication as Record<string, unknown>).id),
      );

      const medicationCount = await fixtureSql`
        select count(*)::integer as count
        from lifemate.medications
        where owner_person_id=${personId}::uuid
      `;
      const planCount = await fixtureSql`
        select count(*)::integer as count
        from lifemate.treatment_plans
        where patient_person_id=${personId}::uuid
      `;
      const medicationAudits = await fixtureSql`
        select count(*)::integer as count
        from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid
          and action='medication.created'
      `;
      assertEquals(medicationCount[0].count, 1);
      assertEquals(planCount[0].count, 2);
      assertEquals(medicationAudits[0].count, 1);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanupFixture(appUserId, accountId, personId);
    }
  },
});

Deno.test({
  name:
    "concurrent quota-boundary treatment creates serialize and never exceed the free medication quota",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const store = createPersonTreatmentCreateStore(databaseUrl);

    try {
      await replaceBootstrapIdentity(
        appUserId,
        accountId,
        personId,
        authSubject,
      );

      for (const index of [1, 2]) {
        await fixtureSql`
          insert into lifemate.medications
            (id,owner_person_id,name,strength_text,form,notes,version,
             created_at_utc,updated_at_utc)
          values
            (${crypto.randomUUID()}::uuid,${personId}::uuid,
             ${`quota-seed-${index}-${crypto.randomUUID()}`},'5 mg','tablet',
             'synthetic quota fixture',1,now(),now())
        `;
      }

      const results = await Promise.allSettled([
        store.createTreatment(
          appUserId,
          treatmentBody(`quota-contender-a-${crypto.randomUUID()}`),
        ),
        store.createTreatment(
          appUserId,
          treatmentBody(`quota-contender-b-${crypto.randomUUID()}`),
        ),
      ]);
      const fulfilled = results.filter((result) => result.status === "fulfilled");
      const rejected = results.filter((result) => result.status === "rejected");
      assertEquals(fulfilled.length, 1);
      assertEquals(rejected.length, 1);
      const rejection = rejected[0] as PromiseRejectedResult;
      assertEquals(rejection.reason instanceof ApiError, true);
      assertEquals((rejection.reason as ApiError).status, 403);
      assertEquals(
        (rejection.reason as ApiError).code,
        "premium_required_quota_reached",
      );

      const medicationCount = await fixtureSql`
        select count(*)::integer as count
        from lifemate.medications
        where owner_person_id=${personId}::uuid
      `;
      const planCount = await fixtureSql`
        select count(*)::integer as count
        from lifemate.treatment_plans
        where patient_person_id=${personId}::uuid
      `;
      assertEquals(medicationCount[0].count, 3);
      assertEquals(planCount[0].count, 1);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanupFixture(appUserId, accountId, personId);
    }
  },
});

Deno.test({
  name:
    "failure after medication persistence rolls back completely and a clean retry succeeds once",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const marker = `rollback-retry-${crypto.randomUUID()}`;
    const body = treatmentBody(marker);
    const failingStore = createPersonTreatmentCreateStore(databaseUrl, {
      afterMedicationPersisted: () => {
        throw new Error("synthetic_failure_after_medication");
      },
    });

    try {
      await replaceBootstrapIdentity(
        appUserId,
        accountId,
        personId,
        authSubject,
      );

      await assertRejects(
        () => failingStore.createTreatment(appUserId, body),
        Error,
        "synthetic_failure_after_medication",
      );

      const cleanStore = createPersonTreatmentCreateStore(databaseUrl);
      await cleanStore.createTreatment(appUserId, body);

      const medications = await fixtureSql`
        select count(*)::integer as count
        from lifemate.medications
        where owner_person_id=${personId}::uuid and name=${marker}
      `;
      const plans = await fixtureSql`
        select count(*)::integer as count
        from lifemate.treatment_plans
        where patient_person_id=${personId}::uuid
      `;
      const audits = await fixtureSql`
        select action,count(*)::integer as count
        from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid
          and action in ('medication.created','treatment_plan.created')
        group by action
        order by action
      `;
      assertEquals(medications[0].count, 1);
      assertEquals(plans[0].count, 1);
      assertEquals(audits.length, 2);
      assertEquals(audits.every((row) => Number(row.count) === 1), true);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanupFixture(appUserId, accountId, personId);
    }
  },
});

Deno.test({
  name:
    "same treatment request is fail-closed while in progress then replays deterministically after an ambiguous response",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const marker = `idempotent-treatment-${crypto.randomUUID()}`;
    const body = treatmentBody(marker);
    const bodyText = JSON.stringify(body);
    const key = `treatment-${crypto.randomUUID()}`;
    const operation = "POST /api/v1/treatment-plans";
    const idempotency = createMutationIdempotencyStore(
      databaseUrl,
      "integration-only-idempotency-secret-0123456789abcdef",
    );

    let releasePersisted!: () => void;
    let signalPersisted!: () => void;
    const releaseGate = new Promise<void>((resolve) => {
      releasePersisted = resolve;
    });
    const persisted = new Promise<void>((resolve) => {
      signalPersisted = resolve;
    });
    const store = createPersonTreatmentCreateStore(databaseUrl, {
      afterMedicationPersisted: async () => {
        signalPersisted();
        await releaseGate;
      },
    });
    let actionCount = 0;

    try {
      await replaceBootstrapIdentity(
        appUserId,
        accountId,
        personId,
        authSubject,
      );

      const first = idempotency.execute(
        appUserId,
        operation,
        key,
        bodyText,
        async () => {
          actionCount += 1;
          const created = await store.createTreatment(appUserId, body);
          return new Response(JSON.stringify(created), {
            status: 201,
            headers: { "content-type": "application/json" },
          });
        },
      );

      await persisted;
      await assertApiError(
        () =>
          idempotency.execute(
            appUserId,
            operation,
            key,
            bodyText,
            () => {
              actionCount += 1;
              throw new Error("duplicate action must not execute");
            },
          ),
        409,
        "idempotency_in_progress",
      );

      releasePersisted();
      const firstResponse = await first;
      assertEquals(firstResponse.status, 201);
      const firstPayload = await firstResponse.json() as Record<string, unknown>;

      // Model an ambiguous client/network outcome: the successful first response
      // is considered lost by the caller, which retries the identical request.
      const replayed = await idempotency.execute(
        appUserId,
        operation,
        key,
        bodyText,
        () => {
          actionCount += 1;
          throw new Error("completed idempotent action must not execute again");
        },
      );
      const replayPayload = await replayed.json() as Record<string, unknown>;
      assertEquals(replayed.status, 201);
      assertEquals(replayed.headers.get("X-Idempotency-Replayed"), "true");
      assertEquals(replayPayload.id, firstPayload.id);
      assertEquals(actionCount, 1);

      await assertApiError(
        () =>
          idempotency.execute(
            appUserId,
            operation,
            key,
            JSON.stringify({ ...body, doseText: "different logical request" }),
            () => Promise.resolve(new Response(null, { status: 201 })),
          ),
        409,
        "idempotency_key_reused",
      );

      const medicationCount = await fixtureSql`
        select count(*)::integer as count
        from lifemate.medications
        where owner_person_id=${personId}::uuid
      `;
      const planCount = await fixtureSql`
        select count(*)::integer as count
        from lifemate.treatment_plans
        where patient_person_id=${personId}::uuid
      `;
      assertEquals(medicationCount[0].count, 1);
      assertEquals(planCount[0].count, 1);
    } finally {
      releasePersisted();
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await cleanupFixture(appUserId, accountId, personId, [key]);
      await fixtureSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
