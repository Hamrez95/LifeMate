import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "postgres";
import { createClient } from "supabase";
import { loadWorkerDatabaseUrl } from "./runtime_database.ts";

const databaseUrl = await loadWorkerDatabaseUrl();
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get(
  ["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"),
);
const workerToken = Deno.env.get("LIFEMATE_WORKER_TOKEN");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Required worker runtime configuration is missing.");
}

const sql = postgres(databaseUrl, {
  max: 1,
  idle_timeout: 10,
  connect_timeout: 10,
  prepare: false,
});
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const supportedEvents = [
  "care.adherence_projection_refresh_requested",
  "identity.session_revoke_requested",
  "identity.account_deletion_requested",
];

type OutboxMessage = {
  id: string;
  aggregate_type: string;
  aggregate_id: string | null;
  event_type: string;
  payload_json: Record<string, unknown>;
  attempt_count: number;
};

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return response(405, { error: "method_not_allowed" });
  }
  if (!workerToken || workerToken.length < 32) {
    return response(503, { error: "worker_not_configured" });
  }
  const supplied = request.headers.get("x-lifemate-worker-token") ?? "";
  if (!constantTimeEqual(workerToken, supplied)) {
    return response(401, { error: "unauthorized" });
  }

  const workerId = `edge:${crypto.randomUUID()}`;
  const claimed = await sql<OutboxMessage[]>`
    select *
    from integration.claim_outbox_messages_for_events(
      ${workerId}::character varying,
      25,
      ${supportedEvents}::character varying[]
    )
  `;

  let processed = 0;
  let failed = 0;
  for (const message of claimed) {
    try {
      await processMessage(message);
      await sql`
        select integration.complete_outbox_message(
          ${message.id}::uuid,${workerId}::character varying)
      `;
      processed++;
    } catch (error) {
      failed++;
      const code = safeErrorCode(error);
      const retrySeconds = Math.min(
        3600,
        30 * Math.max(1, message.attempt_count),
      );
      await sql`
        select integration.fail_outbox_message(
          ${message.id}::uuid,
          ${workerId}::character varying,
          ${code}::character varying,
          ${retrySeconds}
        )
      `;
      console.warn("LifeMate worker item failed", {
        eventType: message.event_type,
        attempt: message.attempt_count,
        errorCode: code,
      });
    }
  }

  return response(200, { claimed: claimed.length, processed, failed });
});

async function processMessage(message: OutboxMessage): Promise<void> {
  switch (message.event_type) {
    case "care.adherence_projection_refresh_requested": {
      const personId = stringField(message.payload_json, "personId");
      const summaryDate = stringField(message.payload_json, "summaryDate");
      await sql`
        select care.rebuild_daily_adherence_summary(
          ${personId}::uuid,${summaryDate}::date)
      `;
      return;
    }
    case "identity.session_revoke_requested": {
      const accountId = requiredAggregateId(message);
      const authSubject = await authSubjectFor(accountId);
      if (!authSubject) return;
      const { error } = await admin.auth.admin.updateUserById(authSubject, {
        ban_duration: "876000h",
      });
      if (error) {
        throw new Error(`auth_session_revoke:${error.status ?? "error"}`);
      }
      return;
    }
    case "identity.account_deletion_requested": {
      const accountId = requiredAggregateId(message);
      const requestId = stringField(message.payload_json, "requestId");

      const pendingSession = await sql`
        select 1
        from integration.outbox_messages
        where aggregate_id=${accountId}::uuid
          and event_type='identity.session_revoke_requested'
          and status <> 'Processed'
        limit 1
      `;
      if (pendingSession[0]) throw new Error("session_revoke_pending");

      const authSubject = await authSubjectFor(accountId);
      if (authSubject) {
        const { error } = await admin.auth.admin.deleteUser(authSubject, true);
        if (error && error.status !== 404) {
          throw new Error(`auth_delete:${error.status ?? "error"}`);
        }
      }

      const finalized = await sql`
        select identity.finalize_account_deletion(${requestId}::uuid) as ok
      `;
      if (finalized[0]?.ok !== true) {
        throw new Error("deletion_finalize_failed");
      }
      return;
    }
    default:
      throw new Error("unsupported_event");
  }
}

async function authSubjectFor(accountId: string): Promise<string | null> {
  const rows = await sql`
    select auth_subject
    from lifemate.app_users
    where id=${accountId}::uuid
    limit 1
  `;
  const value = rows[0]?.auth_subject;
  return typeof value === "string" && value.length > 0 ? value : null;
}

function requiredAggregateId(message: OutboxMessage): string {
  if (!message.aggregate_id) throw new Error("aggregate_id_missing");
  return message.aggregate_id;
}

function stringField(value: Record<string, unknown>, field: string): string {
  const result = value?.[field];
  if (
    typeof result !== "string" || result.length === 0 || result.length > 256
  ) {
    throw new Error(`invalid_${field}`);
  }
  return result;
}

function safeErrorCode(error: unknown): string {
  const raw = error instanceof Error ? error.message : "worker_error";
  return raw.replace(/[^a-zA-Z0-9:_-]/g, "_").slice(0, 80) || "worker_error";
}

function constantTimeEqual(expected: string, actual: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(expected);
  const b = encoder.encode(actual);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    difference |= (a[i % a.length] ?? 0) ^
      (b[i % Math.max(1, b.length)] ?? 0);
  }
  return difference === 0;
}

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
