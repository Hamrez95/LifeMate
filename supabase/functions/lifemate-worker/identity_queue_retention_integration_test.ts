import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import postgres from "postgres";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) throw new Error("TEST_DATABASE_URL is required.");

const sql = postgres(databaseUrl, { max: 1, prepare: false, idle_timeout: 5, connect_timeout: 5 });

Deno.test({
  name: "privacy-critical deletion lifecycle does not expire by age",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const runId = crypto.randomUUID();
    const workerId = `identity-retention:${runId}`;
    const sessionId = crypto.randomUUID();
    const projectionId = crypto.randomUUID();
    const prefix = `identity-retention:${runId}`;
    try {
      await sql`
        insert into integration.outbox_messages(
          id,aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc
        ) values (
          ${sessionId}::uuid,'account',${crypto.randomUUID()}::uuid,
          'identity.session_revoke_requested',${`${prefix}:session`},'{}'::jsonb,'Pending',now()
        ),(
          ${projectionId}::uuid,'person',${crypto.randomUUID()}::uuid,
          'care.adherence_projection_refresh_requested',${`${prefix}:projection`},
          ${sql.json({ personId: crypto.randomUUID(), summaryDate: "2026-09-05" })},'Pending',now()
        )
      `;
      await sql`
        update integration.outbox_messages
        set max_age_seconds=60,created_at_utc=now()-interval '2 minutes'
        where id in (${sessionId}::uuid,${projectionId}::uuid)
      `;

      const claimed = await sql`
        select * from integration.claim_outbox_messages_for_events(
          ${workerId}::character varying,10,
          ${["identity.session_revoke_requested","care.adherence_projection_refresh_requested"]}::character varying[]
        )
      `;
      assertEquals(claimed.some((row) => String(row.id) === sessionId), true);

      const rows = await sql`
        select id,status,last_error_code from integration.outbox_messages
        where id in (${sessionId}::uuid,${projectionId}::uuid)
      `;
      const session = rows.find((row) => String(row.id) === sessionId);
      const projection = rows.find((row) => String(row.id) === projectionId);
      assertEquals(session?.status, "Processing");
      assertEquals(projection?.status, "DeadLetter");
      assertEquals(projection?.last_error_code, "message_expired");

      const failed = await sql`
        select integration.fail_outbox_message_safely(
          ${sessionId}::uuid,${workerId}::character varying,'retryable_test',30,false
        ) as ok
      `;
      assertEquals(failed[0].ok, true);
      const retriable = await sql`
        select status,dead_lettered_at_utc from integration.outbox_messages where id=${sessionId}::uuid
      `;
      assertEquals(retriable[0].status, "Failed");
      assertEquals(retriable[0].dead_lettered_at_utc, null);
    } finally {
      await sql`delete from integration.outbox_messages where idempotency_key like ${`${prefix}%`}`;
    }
  },
});

addEventListener("unload", () => sql.end({ timeout: 1 }));
