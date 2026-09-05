import postgres from "postgres";

export type AdminSql = ReturnType<typeof postgres>;
export type AdminJsonValue = Parameters<AdminSql["json"]>[0];

export function toAdminJson(value: unknown): AdminJsonValue {
  const serialized = JSON.stringify(value);
  if (serialized === undefined) {
    throw new TypeError("Value is not JSON serializable.");
  }
  return JSON.parse(serialized) as AdminJsonValue;
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

export async function closeAdminSqlClientsForTest(): Promise<void> {
  const current = [...clients.values()];
  clients.clear();
  await Promise.all(current.map((client) => client.end({ timeout: 1 })));
}
