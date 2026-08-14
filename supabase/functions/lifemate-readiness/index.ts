import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "postgres";
import { loadReadinessDatabaseUrl } from "./runtime_database.ts";

const releaseVersion = (
  Deno.env.get("LIFEMATE_RELEASE_VERSION") ?? "unversioned"
).slice(0, 128);
const databaseUrl = await loadReadinessDatabaseUrl();
const sql = postgres(databaseUrl, {
  max: 1,
  idle_timeout: 3,
  connect_timeout: 5,
  prepare: false,
  connection: {
    application_name: "lifemate-readiness",
    statement_timeout: 1500,
    lock_timeout: 500,
    idle_in_transaction_session_timeout: 2000,
  },
});

Deno.serve(async (request: Request) => {
  if (request.method !== "GET") {
    return response(405, { status: "error", code: "method_not_allowed" });
  }

  const startedAt = performance.now();
  try {
    // Frequent monitoring intentionally performs one read-only, constant-cost
    // query through the exact restricted application database identity. Deep
    // grant/RLS/DML verification lives in deployment CI, not this public path.
    const rows = await sql`
      select current_user as role_name, 1::integer as dependency_ready
    `;
    if (
      rows[0]?.role_name !== "lifemate_edge_runtime" ||
      Number(rows[0]?.dependency_ready) !== 1
    ) {
      throw new Error("runtime_identity_not_restricted");
    }

    return response(200, {
      status: "ok",
      database: "application_ready",
      role: "lifemate_edge_runtime",
      service: "lifemate-readiness",
      mode: "lightweight",
      version: releaseVersion,
      durationMs: Math.max(0, Math.round(performance.now() - startedAt)),
    });
  } catch (error) {
    console.warn("LifeMate readiness failed", {
      code: error instanceof Error
        ? error.message.slice(0, 80)
        : "probe_failed",
    });
    return response(503, {
      status: "error",
      database: "application_unavailable",
      service: "lifemate-readiness",
      mode: "lightweight",
      version: releaseVersion,
    });
  }
});

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
