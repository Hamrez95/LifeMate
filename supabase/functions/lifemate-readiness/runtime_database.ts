import postgres from "postgres";

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

export async function loadReadinessDatabaseUrl(): Promise<string> {
  const explicitRuntimeDatabaseUrl = Deno.env.get("LIFEMATE_DB_URL");
  if (explicitRuntimeDatabaseUrl) return explicitRuntimeDatabaseUrl;

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
    return buildRestrictedReadinessDatabaseUrl(bootstrapDatabaseUrl, password);
  } finally {
    await bootstrap.end({ timeout: 2 });
  }
}
