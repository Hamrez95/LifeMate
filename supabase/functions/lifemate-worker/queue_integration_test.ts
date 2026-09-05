import {
  assertEquals,
  assertGreaterOrEqual,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import postgres from "postgres";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");

if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for outbox integration tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name: "outbox queue policy stays bounded, observable and recoverable",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const runId = crypto.randomUUID();
    const prefix = `scale06-test:${runId}`;
    const personId = crypto.randomUUID();
    const summaryDate = "2026-08-14";
    const workerId = `test-worker:${runId}`;

    try {
      await sql`
        insert into integration.outbox_messages(
          aggregate_type, aggregate_id, event_type, idempotency_key,
          payload_json, status, available_at_utc
        ) values (
          'person', ${personId}::uuid,
          'care.adherence_projection_refresh_requested',
          ${`${prefix}:projection:1`},
          ${sql.json({ personId, summaryDate, marker: 1 })},
          'Pending', now()
        )
      `;
      await sql`
        insert into integration.outbox_messages(
          aggregate_type, aggregate_id, event_type, idempotency_key,
          payload_json, status, available_at_utc
        ) values (
          'person', ${personId}::uuid,
          'care.adherence_projection_refresh_requested',
          ${`${prefix}:projection:2`},
          ${sql.json({ personId, summaryDate, marker: 2 })},
          'Pending', now()
        )
      `;

      const coalesced = await sql`
        select id, payload_json, priority, max_attempts, max_age_seconds
        from integration.outbox_messages
        where coalesce_key=${`adherence:${personId}:${summaryDate}`}
          and status in ('Pending','Failed','Processing')
      `;
      assertEquals(coalesced.length, 1);
      assertEquals(Number(coalesced[0].payload_json.marker), 2);
      assertEquals(Number(coalesced[0].priority), 60);
      assertEquals(Number(coalesced[0].max_attempts), 8);
      assertEquals(Number(coalesced[0].max_age_seconds), 21600);

      await sql`
        insert into integration.outbox_messages(
          aggregate_type, aggregate_id, event_type, idempotency_key,
          payload_json, status, available_at_utc
        ) values (
          'account', ${crypto.randomUUID()}::uuid,
          'identity.session_revoke_requested',
          ${`${prefix}:priority`}, '{}'::jsonb, 'Pending', now()
        )
      `;

      const firstClaim = await sql`
        select * from integration.claim_outbox_messages_for_events(
          ${workerId}::character varying,
          1,
          ${[
        "care.adherence_projection_refresh_requested",
        "identity.session_revoke_requested",
      ]}::character varying[]
        )
      `;
      assertEquals(firstClaim.length, 1);
      assertEquals(
        firstClaim[0].event_type,
        "identity.session_revoke_requested",
      );
      const firstClaimPolicy = await sql`
      select priority
      from integration.outbox_messages
      where id=${firstClaim[0].id}::uuid
    `;
      assertEquals(Number(firstClaimPolicy[0].priority), 5);

      const completed = await sql`
        select integration.complete_outbox_message(
          ${firstClaim[0].id}::uuid,
          ${workerId}::character varying
        ) as ok
      `;
      assertEquals(completed[0].ok, true);

      const projectionClaim = await sql`
        select * from integration.claim_outbox_messages_for_events(
          ${workerId}::character varying,
          1,
          ${[
        "care.adherence_projection_refresh_requested",
      ]}::character varying[]
        )
      `;
      assertEquals(projectionClaim.length, 1);

      const failed = await sql`
        select integration.fail_outbox_message_safely(
          ${projectionClaim[0].id}::uuid,
          ${workerId}::character varying,
          'invalid_test_payload'::character varying,
          10,
          true
        ) as ok
      `;
      assertEquals(failed[0].ok, true);

      const dead = await sql`
        select status, dead_lettered_at_utc, last_error_code
        from integration.outbox_messages
        where id=${projectionClaim[0].id}::uuid
      `;
      assertEquals(dead[0].status, "DeadLetter");
      assertEquals(dead[0].last_error_code, "invalid_test_payload");
      assertEquals(dead[0].dead_lettered_at_utc instanceof Date, true);

      const metrics = await sql`
        select * from integration.outbox_queue_metrics(
          ${[
        "care.adherence_projection_refresh_requested",
        "identity.session_revoke_requested",
      ]}::character varying[]
        )
      `;
      assertGreaterOrEqual(Number(metrics[0].dead_letter_count), 1);
      assertGreaterOrEqual(Number(metrics[0].oldest_ready_age_seconds), 0);

      const requeued = await sql`
        select integration.requeue_dead_letter_outbox_message(
          ${projectionClaim[0].id}::uuid,
          'integration_test'::character varying
        ) as ok
      `;
      assertEquals(requeued[0].ok, true);
      const requeuedRow = await sql`
        select status, attempt_count, dead_lettered_at_utc
        from integration.outbox_messages
        where id=${projectionClaim[0].id}::uuid
      `;
      assertEquals(requeuedRow[0].status, "Failed");
      assertEquals(Number(requeuedRow[0].attempt_count), 0);
      assertEquals(requeuedRow[0].dead_lettered_at_utc, null);

      // Privacy-critical identity lifecycle messages are intentionally
      // non-expiring. Exercise generic age expiry with a projection refresh
      // event so this queue-safety test does not contradict that invariant.
      const expiredId = crypto.randomUUID();
      const expiredPersonId = crypto.randomUUID();
      const expiredSummaryDate = "2026-08-13";
      await sql`
        insert into integration.outbox_messages(
          id, aggregate_type, aggregate_id, event_type, idempotency_key,
          payload_json, status, available_at_utc
        ) values (
          ${expiredId}::uuid, 'person', ${expiredPersonId}::uuid,
          'care.adherence_projection_refresh_requested', ${`${prefix}:expired`},
          ${sql.json({
        personId: expiredPersonId,
        summaryDate: expiredSummaryDate,
      })},
          'Pending', now()
        )
      `;
      await sql`
        update integration.outbox_messages
        set max_age_seconds=60, created_at_utc=now()-interval '2 minutes'
        where id=${expiredId}::uuid
      `;
      await sql`
        select * from integration.claim_outbox_messages_for_events(
          ${workerId}::character varying,
          10,
          ${["care.adherence_projection_refresh_requested"]}::character varying[]
        )
      `;
      const expired = await sql`
        select status, last_error_code
        from integration.outbox_messages
        where id=${expiredId}::uuid
      `;
      assertEquals(expired[0].status, "DeadLetter");
      assertEquals(expired[0].last_error_code, "message_expired");

      const staleId = crypto.randomUUID();
      await sql`
        insert into integration.outbox_messages(
          id, aggregate_type, aggregate_id, event_type, idempotency_key,
          payload_json, status, available_at_utc
        ) values (
          ${staleId}::uuid, 'account', ${crypto.randomUUID()}::uuid,
          'identity.session_revoke_requested', ${`${prefix}:stale`},
          '{}'::jsonb, 'Pending', now()
        )
      `;
      await sql`
        update integration.outbox_messages
        set status='Processing', locked_by='dead-worker',
            locked_at_utc=now()-interval '11 minutes'
        where id=${staleId}::uuid
      `;
      const recovered = await sql`
        select * from integration.claim_outbox_messages_for_events(
          ${workerId}::character varying,
          10,
          ${["identity.session_revoke_requested"]}::character varying[]
        )
      `;
      assertEquals(
        recovered.some((row) => String(row.id) === staleId),
        true,
      );
    } finally {
      await sql`
        delete from integration.outbox_messages
        where idempotency_key like ${`${prefix}%`}
      `;
    }
  },
});

addEventListener("unload", () => {
  sql.end({ timeout: 1 });
});
