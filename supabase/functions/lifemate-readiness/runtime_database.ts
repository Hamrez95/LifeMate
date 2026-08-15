import postgres from "postgres";

export type ReadinessDatabaseTransport =
  | "transaction_pooler"
  | "direct_or_other";

export type ReadinessDatabaseConfig = {
  databaseUrl: string;
  databaseTransport: ReadinessDatabaseTransport;
  transactionPoolerRequired: boolean;
};

export function isReadinessTransactionPoolerUrl(value: string): boolean {
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "postgres:" && parsed.protocol !== "postgresql:") {
      return false;
    }
    if (parsed.port !== "6543") return false;
    const host = parsed.hostname.toLowerCase();
    return host.endsWith(".pooler.supabase.com") ||
      (host.startsWith("db.") && host.endsWith(".supabase.co"));
  } catch {
    return false;
  }
}

export function parseReadinessBoolean(
  name: string,
  value: string | null | undefined,
  fallback: boolean,
): boolean {
  if (value === null || value === undefined || value.trim() === "") {
    return fallback;
  }
  const normalized = value.trim().toLowerCase();
  if (normalized === "true") return true;
  if (normalized === "false") return false;
  throw new Error(`${name} must be true or false.`);
}

export function buildRestrictedReadinessDatabaseUrl(
  bootstrapDatabaseUrl: string,
  password: string,
): string {
  if (password.length < 32) {
    throw new Error("Restricted Edge database password is too short.");
  }
  const parsed = new URL(bootstrapDatabaseUrl);
  const currentUser = decodeURIComponent(parsed.username);
  if (!currentUser) throw new Error("Database URL is missing a username.");
  const dot = currentUser.indexOf(".");
  const poolerSuffix = dot >= 0 ? currentUser.slice(dot) : "";
  parsed.username = `lifemate_edge_runtime${poolerSuffix}`;
  parsed.password = password;
  return parsed.toString();
}

export function classifyReadinessDatabaseTransport(
  databaseUrl: string,
): ReadinessDatabaseTransport {
  return isReadinessTransactionPoolerUrl(databaseUrl)
    ? "transaction_pooler"
    : "direct_or_other";
}

export function validateReadinessDatabaseTransport(
  databaseUrl: string,
  transactionPoolerRequired: boolean,
): void {
  if (
    transactionPoolerRequired &&
    !isReadinessTransactionPoolerUrl(databaseUrl)
  ) {
    throw new Error(
      "LifeMate readiness requires a Supabase transaction-pooler database URL on port 6543.",
    );
  }
}

export async function loadReadinessDatabaseConfig(): Promise<
  ReadinessDatabaseConfig
> {
  const explicitRuntimeDatabaseUrl = Deno.env.get("LIFEMATE_DB_URL");
  const transactionPoolerRequired = parseReadinessBoolean(
    "LIFEMATE_REQUIRE_TRANSACTION_POOLER",
    Deno.env.get("LIFEMATE_REQUIRE_TRANSACTION_POOLER"),
    false,
  );

  let databaseUrl = explicitRuntimeDatabaseUrl ?? null;
  if (!databaseUrl) {
    const bootstrapDatabaseUrl = Deno.env.get("SUPABASE_DB_URL");
    if (!bootstrapDatabaseUrl) {
      throw new Error("SUPABASE_DB_URL is missing.");
    }

    const bootstrap = postgres(bootstrapDatabaseUrl, {
      max: 1,
      idle_timeout: 3,
      connect_timeout: 5,
      prepare: false,
      connection: {
        application_name: "lifemate-readiness-bootstrap",
        statement_timeout: 1500,
        lock_timeout: 500,
        idle_in_transaction_session_timeout: 2000,
      },
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
      databaseUrl = buildRestrictedReadinessDatabaseUrl(
        bootstrapDatabaseUrl,
        password,
      );
    } finally {
      await bootstrap.end({ timeout: 2 });
    }
  }

  validateReadinessDatabaseTransport(databaseUrl, transactionPoolerRequired);
  return {
    databaseUrl,
    databaseTransport: classifyReadinessDatabaseTransport(databaseUrl),
    transactionPoolerRequired,
  };
}
