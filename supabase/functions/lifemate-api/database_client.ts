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
      statement_timeout: "5000",
      lock_timeout: "2000",
      idle_in_transaction_session_timeout: "5000",
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
    code.startsWith("08") ||
    /too many clients|remaining connection slots|connection (?:refused|terminated|closed)|database system is starting up|statement timeout|canceling statement due to statement timeout/i
      .test(message);
}

export async function closeLifeMateSqlClientsForTest(): Promise<void> {
  const current = [...clients.values()];
  clients.clear();
  await Promise.all(current.map((client) => client.end({ timeout: 1 })));
}
