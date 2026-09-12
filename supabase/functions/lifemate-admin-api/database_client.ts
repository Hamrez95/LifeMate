import postgres from "postgres";

type RawAdminSql = ReturnType<typeof postgres>;

type AdminSqlJsonCompatibility = {
  json(value: unknown): ReturnType<RawAdminSql["json"]>;
};

// Preserve every callable/generic postgres.js tagged-template signature while
// widening only the JSON encoder used for already-validated admin payloads.
// Intersecting (rather than Omit<>-rebuilding) the client is important because
// the SQL client itself is callable.
export type AdminSql = RawAdminSql & AdminSqlJsonCompatibility;

export function encodeAdminJson(
  sql: AdminSql,
  value: unknown,
): ReturnType<RawAdminSql["json"]> {
  // postgres.js 3.4.7 models JSON recursively more narrowly than the validated
  // Record<string, unknown> DTOs used by Admin services. The runtime encoder
  // accepts JSON-serializable values; keep the compatibility cast centralized.
  return sql.json(value as Parameters<RawAdminSql["json"]>[0]);
}

const clients = new Map<string, AdminSql>();

export function getAdminSql(databaseUrl: string): AdminSql {
  const current = clients.get(databaseUrl);
  if (current) return current;

  const client = postgres(databaseUrl, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    prepare: false,
  }) as AdminSql;
  clients.set(databaseUrl, client);
  return client;
}

// Privacy/consent code historically used this semantic name even though it
// shares the same canonical LifeMate Postgres connection. Preserve the alias
// so callers do not create a second client pool or bypass the common options.
export const getLifeMateSql = getAdminSql;

export function isPostgresUnavailable(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const value = error as Record<string, unknown>;
  const code = String(value.code ?? "");
  const message = String(value.message ?? "");
  return code === "53300" ||
    code === "57P03" ||
    code.startsWith("08") ||
    /too many clients|remaining connection slots|connection (?:refused|terminated|closed)|database system is starting up/i
      .test(message);
}

export async function closeAdminSqlClientsForTest(): Promise<void> {
  const current = [...clients.values()];
  clients.clear();
  await Promise.all(current.map((client) => client.end({ timeout: 1 })));
}
