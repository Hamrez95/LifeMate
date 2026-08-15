import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { getLifeMateSql } from "./database_client.ts";
import { json } from "./http.ts";
import { createMutationIdempotencyStore, requestHash } from "./idempotency.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");

if (databaseUrl) {
  Deno.test("durable idempotency tokenizes actors, replays and serializes duplicates", async () => {
    const sql = getLifeMateSql(databaseUrl);
    const secret = "test-idempotency-response-secret-0000000000000001";
    const store = createMutationIdempotencyStore(databaseUrl, secret);
    const actor = "10000000-0000-4000-8000-000000000137";
    const operation = "POST /api/v1/test-idempotency";
    const replayKey = "scale05-replay-0001";
    const concurrentKey = "scale05-concurrent-0001";
    const legacyKey = "scale05-legacy-0001";

    await sql`
      delete from lifemate.idempotency_keys
      where operation=${operation}
        and idempotency_key in (${replayKey}, ${concurrentKey}, ${legacyKey})
    `;

    try {
      let sideEffects = 0;
      const first = await store.execute(
        actor,
        operation,
        replayKey,
        '{"dose":"500"}',
        async () => {
          sideEffects += 1;
          return json({ id: "resource-1", version: 1 }, 201);
        },
      );
      assertEquals(first.status, 201);
      assertEquals(sideEffects, 1);

      const storedEnvelopeRows = await sql`
        select actor_auth_subject, actor_subject_token, response_body
        from lifemate.idempotency_keys
        where operation=${operation}
          and idempotency_key=${replayKey}
        limit 1
      `;
      assertEquals(storedEnvelopeRows[0]?.actor_auth_subject, null);
      const storedActorToken = String(
        storedEnvelopeRows[0]?.actor_subject_token ?? "",
      );
      assert(/^[0-9a-f]{64}$/.test(storedActorToken));
      assert(storedActorToken !== actor);
      const storedEnvelope = String(storedEnvelopeRows[0]?.response_body ?? "");
      assert(storedEnvelope.startsWith("v1."));
      assert(!storedEnvelope.includes("resource-1"));

      const replay = await store.execute(
        actor,
        operation,
        replayKey,
        '{"dose":"500"}',
        async () => {
          sideEffects += 1;
          return json({ id: "duplicate" }, 201);
        },
      );
      assertEquals(replay.status, 201);
      assertEquals(replay.headers.get("x-idempotency-replayed"), "true");
      assertEquals(await replay.json(), { id: "resource-1", version: 1 });
      assertEquals(sideEffects, 1);

      const conflict = await assertRejects(
        () =>
          store.execute(
            actor,
            operation,
            replayKey,
            '{"dose":"1000"}',
            async () => json({ id: "conflict" }, 201),
          ),
        ApiError,
      );
      assertEquals(conflict.code, "idempotency_key_reused");

      await sql`
        update lifemate.idempotency_keys
        set expires_at_utc=now() - interval '1 second'
        where operation=${operation}
          and idempotency_key=${replayKey}
      `;
      const afterExpiry = await store.execute(
        actor,
        operation,
        replayKey,
        '{"dose":"1000"}',
        async () => {
          sideEffects += 1;
          return json({ id: "resource-2", version: 1 }, 201);
        },
      );
      assertEquals(await afterExpiry.json(), { id: "resource-2", version: 1 });
      assertEquals(sideEffects, 2);

      const legacyHash = await requestHash('{"legacy":true}');
      await sql`
        insert into lifemate.idempotency_keys(
          actor_auth_subject,actor_subject_token,operation,idempotency_key,
          request_hash,status,response_status,response_body,
          created_at_utc,updated_at_utc,expires_at_utc
        ) values(
          ${actor}::uuid,null,${operation},${legacyKey},${legacyHash},
          'Processing',null,null,now(),now(),now()+interval '24 hours'
        )
      `;
      const legacyInProgress = await assertRejects(
        () =>
          store.execute(
            actor,
            operation,
            legacyKey,
            '{"legacy":true}',
            async () => json({ id: "must-not-run" }, 201),
          ),
        ApiError,
      );
      assertEquals(legacyInProgress.code, "idempotency_in_progress");

      let signalStarted!: () => void;
      const started = new Promise<void>((resolve) => signalStarted = resolve);
      let releaseFirst!: () => void;
      const release = new Promise<void>((resolve) => releaseFirst = resolve);
      let concurrentEffects = 0;

      const pending = store.execute(
        actor,
        operation,
        concurrentKey,
        '{"event":"taken"}',
        async () => {
          concurrentEffects += 1;
          signalStarted();
          await release;
          return json({ id: "event-1" }, 200);
        },
      );
      await started;

      const inProgress = await assertRejects(
        () =>
          store.execute(
            actor,
            operation,
            concurrentKey,
            '{"event":"taken"}',
            async () => {
              concurrentEffects += 1;
              return json({ id: "event-duplicate" }, 200);
            },
          ),
        ApiError,
      );
      assertEquals(inProgress.code, "idempotency_in_progress");
      assertEquals(concurrentEffects, 1);

      releaseFirst();
      const completed = await pending;
      assertEquals(completed.status, 200);

      const finalReplay = await store.execute(
        actor,
        operation,
        concurrentKey,
        '{"event":"taken"}',
        async () => {
          concurrentEffects += 1;
          return json({ id: "event-duplicate" }, 200);
        },
      );
      assertEquals(await finalReplay.json(), { id: "event-1" });
      assertEquals(concurrentEffects, 1);
    } finally {
      await sql`
        delete from lifemate.idempotency_keys
        where operation=${operation}
          and idempotency_key in (${replayKey}, ${concurrentKey}, ${legacyKey})
      `;
    }
  });
}
