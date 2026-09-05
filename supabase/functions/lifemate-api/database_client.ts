import postgres from "postgres";

export type LifeMateSql = ReturnType<typeof postgres>;

const clients = new Map<string, LifeMateSql>();

export function lifeMateDatabaseClientOptions(
  applicationName = "lifemate-api",
) {
  return {
    // One client connection per Edge isolate. Server-side Supavisor transaction
    // pooling is responsible for multiplexing many transient Edge clients onto
    // the finite PostgreSQL connection budget.
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    max_lifetime: 60 * 10,
    prepare: false,
    connection: {
      application_name: applicationName,
      statement_timeout: 5000,
      lock_timeout: 2000,
      // ContactPoint writes intentionally perform bounded WebCrypto work while
      // their surrounding database transaction stays open so legacy Profile and
      // canonical ContactPoint state commit atomically. Five seconds was too
      // tight on cold CI/Edge isolates and could terminate a healthy transaction
      // between SQL statements. Keep the guard finite while allowing that
      // expected non-SQL work to complete.
      idle_in_transaction_session_timeout: 15000,
    },
  };
}

/// Every Edge isolate shares one deliberately small postgres.js pool across all
/// LifeMate stores. Five independent max=2 pools previously allowed a normal
/// application startup to exhaust the direct database connection allowance.
export function getLifeMateSql(databaseUrl: string): LifeMateSql {
  const existing = clients.get(databaseUrl);
  if (existing) return existing;

  const client = postgres(databaseUrl, lifeMateDatabaseClientOptions());
  clients.set(databaseUrl, client);
  return client;
}

export function isPostgresUnavailable(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const value = error as Record<string, unknown>;
  const code = String(value.code ?? "");
  const message = String(value.message ?? "");
  return code === "53300" ||
    code === "57P03" ||
    code === "57014" ||
    code === "55P03" ||
    code.startsWith("08") ||
    /too many clients|remaining connection slots|connection (?:refused|terminated|closed)|database system is starting up|statement timeout|lock timeout|canceling statement due to (?:statement|lock) timeout/i
      .test(message);
}

export async function closeLifeMateSqlClientsForTest(): Promise<void> {
  const current = [...clients.values()];
  clients.clear();
  await Promise.all(current.map((client) => client.end({ timeout: 1 })));
}
