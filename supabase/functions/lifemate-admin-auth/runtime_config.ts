import postgres from "postgres";

export type WorkforceAuthConfig = {
  databaseUrl: string;
  supabaseUrl: string;
  anonKey: string;
  serviceRoleKey: string;
  allowedOrigins: ReadonlySet<string>;
};

function readDictionary(name: string): Record<string, string> {
  const raw = Deno.env.get(name);
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {};
    }
    return Object.fromEntries(
      Object.entries(parsed).filter((entry): entry is [string, string] =>
        typeof entry[1] === "string"
      ),
    );
  } catch {
    return {};
  }
}

async function restrictedDatabaseUrl(
  bootstrapDatabaseUrl: string,
): Promise<string> {
  const sql = postgres(bootstrapDatabaseUrl, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    prepare: false,
  });
  try {
    const rows = await sql`
      select decrypted_secret
      from vault.decrypted_secrets
      where name='lifemate_admin_runtime_password'
      limit 1
    `;
    const password = rows[0]?.decrypted_secret;
    if (typeof password !== "string" || password.length < 32) {
      throw new Error("Restricted Admin runtime credential is unavailable.");
    }
    const parsed = new URL(bootstrapDatabaseUrl);
    const currentUser = decodeURIComponent(parsed.username);
    const dot = currentUser.indexOf(".");
    const suffix = dot >= 0 ? currentUser.slice(dot) : "";
    parsed.username = `lifemate_admin_runtime${suffix}`;
    parsed.password = password;
    return parsed.toString();
  } finally {
    await sql.end({ timeout: 5 });
  }
}

export async function loadWorkforceAuthConfig(): Promise<WorkforceAuthConfig> {
  const bootstrapDatabaseUrl = Deno.env.get("SUPABASE_DB_URL");
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "");
  const publishableKeys = readDictionary("SUPABASE_PUBLISHABLE_KEYS");
  const anonKey = publishableKeys.default ?? Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!bootstrapDatabaseUrl || !supabaseUrl || !anonKey || !serviceRoleKey) {
    throw new Error(
      "Required workforce auth runtime configuration is missing.",
    );
  }

  const allowedOrigins = new Set(
    (Deno.env.get("LIFEMATE_ADMIN_ALLOWED_ORIGINS") ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
  if (allowedOrigins.size === 0) {
    throw new Error("Workforce auth origin allow-list is empty.");
  }

  return {
    databaseUrl: await restrictedDatabaseUrl(bootstrapDatabaseUrl),
    supabaseUrl,
    anonKey,
    serviceRoleKey,
    allowedOrigins,
  };
}
