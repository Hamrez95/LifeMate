import postgres from "postgres";

type PostgresSql = ReturnType<typeof postgres>;
type PostgresJsonResult = ReturnType<PostgresSql["json"]>;

export type AdminSql = PostgresSql & {
  // postgres serializes plain request/DB JSON objects at runtime, while its
  // current Deno typings reject structurally validated Record/object values.
  json(value: Parameters<PostgresSql["json"]>[0] | object): PostgresJsonResult;
};

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

// Compatibility name used by the privacy/consent store. Both Admin and
// consent read models intentionally use the same restricted database URL.
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
