import postgres from "postgres";

const workerRole = "lifemate_worker_runtime";

export function buildWorkerDatabaseUrl(
  bootstrapDatabaseUrl: string,
  password: string,
): string {
  if (password.length < 32) {
    throw new Error("Restricted worker database password is too short.");
  }
  const parsed = new URL(bootstrapDatabaseUrl);
  const currentUser = decodeURIComponent(parsed.username);
  if (!currentUser) throw new Error("Database URL is missing a username.");
  const dot = currentUser.indexOf(".");
  const suffix = dot >= 0 ? currentUser.slice(dot) : "";
  parsed.username = `${workerRole}${suffix}`;
  parsed.password = password;
  return parsed.toString();
}

export function isRestrictedWorkerDatabaseUrl(databaseUrl: string): boolean {
  try {
    const parsed = new URL(databaseUrl);
    const username = decodeURIComponent(parsed.username);
    return username === workerRole || username.startsWith(`${workerRole}.`);
  } catch {
    return false;
  }
}

export async function loadWorkerDatabaseUrl(): Promise<string> {
  const explicit = Deno.env.get("LIFEMATE_WORKER_DB_URL");
  if (explicit && isRestrictedWorkerDatabaseUrl(explicit)) return explicit;

  const bootstrap = Deno.env.get("SUPABASE_DB_URL");
  if (!bootstrap) {
    throw new Error(
      explicit
        ? "LIFEMATE_WORKER_DB_URL is not a restricted worker-role URL and SUPABASE_DB_URL is missing."
        : "SUPABASE_DB_URL is missing.",
    );
  }

  const sql = postgres(bootstrap, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    prepare: false,
  });
  try {
    const rows = await sql`
      select decrypted_secret
      from vault.decrypted_secrets
      where name='lifemate_worker_runtime_password'
      limit 1
    `;
    const password = rows[0]?.decrypted_secret;
    if (typeof password !== "string" || password.length < 32) {
      throw new Error(
        "Restricted LifeMate worker database credential is missing. Refusing elevated database fallback.",
      );
    }
    return buildWorkerDatabaseUrl(bootstrap, password);
  } finally {
    await sql.end({ timeout: 5 });
  }
}
