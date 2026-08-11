import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "postgres";

const bootstrapDatabaseUrl = Deno.env.get("SUPABASE_DB_URL");
const explicitRuntimeDatabaseUrl = Deno.env.get("LIFEMATE_DB_URL");
const releaseVersion = (
  Deno.env.get("LIFEMATE_RELEASE_VERSION") ?? "unversioned"
).slice(0, 128);

if (!bootstrapDatabaseUrl) {
  throw new Error("SUPABASE_DB_URL is missing.");
}

async function restrictedDatabaseUrl(): Promise<string> {
  if (explicitRuntimeDatabaseUrl) return explicitRuntimeDatabaseUrl;

  const bootstrap = postgres(bootstrapDatabaseUrl!, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    prepare: false,
  });
  try {
    const rows = await bootstrap`
      select decrypted_secret
      from vault.decrypted_secrets
      where name='lifemate_edge_runtime_password'
      limit 1
    `;
    const password = rows[0]?.decrypted_secret;
    if (typeof password !== "string" || password.length < 32) {
      throw new Error("Restricted Edge database credential is missing.");
    }
    const parsed = new URL(bootstrapDatabaseUrl!);
    const currentUser = decodeURIComponent(parsed.username);
    const dot = currentUser.indexOf(".");
    const poolerSuffix = dot >= 0 ? currentUser.slice(dot) : "";
    parsed.username = `lifemate_edge_runtime${poolerSuffix}`;
    parsed.password = password;
    return parsed.toString();
  } finally {
    await bootstrap.end({ timeout: 5 });
  }
}

const databaseUrl = await restrictedDatabaseUrl();
const sql = postgres(databaseUrl, {
  max: 1,
  idle_timeout: 10,
  connect_timeout: 10,
  prepare: false,
});

Deno.serve(async (request: Request) => {
  if (request.method !== "GET") {
    return response(405, { status: "error", code: "method_not_allowed" });
  }
  try {
    // These probes contain no user data, but they require the same restricted
    // schema/table grants and RLS path used by the real application runtime.
    const applications = await sql`
      select code
      from ecosystem.applications
      where code='wellmate' and status='Active'
      limit 1
    `;
    if (applications[0]?.code !== "wellmate") {
      throw new Error("wellmate_application_missing");
    }
    await sql`select id from lifemate.health_observations where false`;
    await sql`select id from lifemate.dose_occurrences where false`;

    return response(200, {
      status: "ok",
      database: "application_ready",
      role: "restricted",
      service: "lifemate-readiness",
      version: releaseVersion,
    });
  } catch (error) {
    console.warn("LifeMate readiness failed", {
      code: error instanceof Error ? error.message.slice(0, 80) : "probe_failed",
    });
    return response(503, {
      status: "error",
      database: "application_unavailable",
      service: "lifemate-readiness",
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
