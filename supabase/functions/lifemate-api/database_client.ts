import postgres from "postgres";

export type LifeMateSql = ReturnType<typeof postgres>;

const clients = new Map<string, LifeMateSql>();

/// Every Edge isolate shares one deliberately small postgres.js pool across all
/// LifeMate stores. Five independent max=2 pools previously allowed a normal
/// application startup to exhaust the direct database connection allowance.
export function getLifeMateSql(databaseUrl: string): LifeMateSql {
  const existing = clients.get(databaseUrl);
  if (existing) return existing;

  const client = postgres(databaseUrl, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    prepare: false,
  });
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
    code.startsWith("08") ||
    /too many clients|remaining connection slots|connection (?:refused|terminated|closed)|database system is starting up/i
      .test(message);
}

export async function closeLifeMateSqlClientsForTest(): Promise<void> {
  const current = [...clients.values()];
  clients.clear();
  await Promise.all(current.map((client) => client.end({ timeout: 1 })));
}
