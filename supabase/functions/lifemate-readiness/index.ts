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
    const identity = await sql`
      select current_user as role_name,
             r.rolbypassrls,
             r.rolsuper,
             r.rolcreaterole,
             r.rolcreatedb,
             r.rolconnlimit
      from pg_roles r
      where r.rolname=current_user
      limit 1
    `;
    const role = identity[0];
    if (
      role?.role_name !== "lifemate_edge_runtime" ||
      role?.rolbypassrls !== false ||
      role?.rolsuper !== false ||
      role?.rolcreaterole !== false ||
      role?.rolcreatedb !== false ||
      Number(role?.rolconnlimit) !== 20
    ) {
      throw new Error("runtime_identity_not_restricted");
    }

    const applications = await sql`
      select code
      from ecosystem.applications
      where code='wellmate' and status='Active'
      limit 1
    `;
    if (applications[0]?.code !== "wellmate") {
      throw new Error("wellmate_application_missing");
    }

    // Verify the healthcare objects needed by the real API still have both the
    // required table grants and the expected role-bound RLS policy definition.
    const healthContract = await sql`
      select
        has_table_privilege(current_user, 'lifemate.health_observations', 'SELECT') as can_select,
        has_table_privilege(current_user, 'lifemate.health_observations', 'INSERT') as can_insert,
        has_table_privilege(current_user, 'lifemate.health_observations', 'UPDATE') as can_update,
        has_table_privilege(current_user, 'lifemate.health_observations', 'DELETE') as can_delete,
        exists (
          select 1
          from pg_policies
          where schemaname='lifemate'
            and tablename='health_observations'
            and policyname='lifemate_edge_runtime_access'
            and cmd='ALL'
            and 'lifemate_edge_runtime'=any(roles)
            and coalesce(qual, '')='true'
            and coalesce(with_check, '')='true'
        ) as expected_policy
    `;
    const health = healthContract[0];
    if (
      health?.can_select !== true ||
      health?.can_insert !== true ||
      health?.can_update !== true ||
      health?.can_delete !== true ||
      health?.expected_policy !== true
    ) {
      throw new Error("health_runtime_contract_broken");
    }

    await sql`select id from lifemate.health_observations where false`;
    await sql`select id from lifemate.dose_occurrences where false`;

    // Exercise real SELECT/INSERT/UPDATE/DELETE through FORCE RLS on a dedicated
    // synthetic table. No patient/profile/treatment data is created or read.
    const probeId = crypto.randomUUID();
    await sql.begin(async (tx) => {
      const seed = await tx`
        select marker
        from security.runtime_readiness_probe
        where id='123e4567-e89b-42d3-a456-426614174888'::uuid
        limit 1
      `;
      if (seed[0]?.marker !== "lifemate-readiness-seed") {
        throw new Error("readiness_seed_not_visible");
      }
      await tx`
        insert into security.runtime_readiness_probe(id, marker)
        values (${probeId}::uuid, 'probe-created')
      `;
      const updated = await tx`
        update security.runtime_readiness_probe
        set marker='probe-updated', updated_at_utc=now()
        where id=${probeId}::uuid
        returning marker
      `;
      if (updated[0]?.marker !== "probe-updated") {
        throw new Error("readiness_update_failed");
      }
      const deleted = await tx`
        delete from security.runtime_readiness_probe
        where id=${probeId}::uuid
        returning id
      `;
      if (deleted.length !== 1) {
        throw new Error("readiness_delete_failed");
      }
    });

    return response(200, {
      status: "ok",
      database: "application_ready",
      role: "lifemate_edge_runtime",
      service: "lifemate-readiness",
      version: releaseVersion,
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
