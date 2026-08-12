import postgres from "postgres";

export type AdminRuntimeConfig = {
  databaseUrl: string;
  supabaseUrl: string;
  publishableKey: string;
  allowedOrigins: ReadonlySet<string>;
  bootstrapAuthSubject: string | null;
  releaseVersion: string;
};

export function buildRestrictedDatabaseUrl(
  bootstrapDatabaseUrl: string,
  roleName: string,
  password: string,
): string {
  if (!/^[a-z][a-z0-9_]{2,62}$/i.test(roleName)) {
    throw new Error("Invalid restricted database role name.");
  }
  if (password.length < 32) {
    throw new Error(
      "Restricted database password must be at least 32 characters.",
    );
  }

  const parsed = new URL(bootstrapDatabaseUrl);
  const currentUser = decodeURIComponent(parsed.username);
  if (!currentUser) throw new Error("Database URL is missing a username.");
  const dot = currentUser.indexOf(".");
  const poolerSuffix = dot >= 0 ? currentUser.slice(dot) : "";
  parsed.username = `${roleName}${poolerSuffix}`;
  parsed.password = password;
  return parsed.toString();
}

function readDictionary(name: string): Record<string, string> {
  const raw = Deno.env.get(name);
  if (!raw) return {};
  try {
    const value = JSON.parse(raw);
    if (!value || typeof value !== "object" || Array.isArray(value)) return {};
    return Object.fromEntries(
      Object.entries(value).filter((entry): entry is [string, string] =>
        typeof entry[1] === "string"
      ),
    );
  } catch {
    return {};
  }
}

async function readAdminRuntimePassword(
  bootstrapDatabaseUrl: string,
): Promise<string | null> {
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
    return typeof rows[0]?.decrypted_secret === "string"
      ? rows[0].decrypted_secret
      : null;
  } catch {
    return null;
  } finally {
    await sql.end({ timeout: 5 });
  }
}

export async function loadRuntimeConfig(): Promise<AdminRuntimeConfig> {
  const bootstrapDatabaseUrl = Deno.env.get("SUPABASE_DB_URL");
  const explicitDatabaseUrl = Deno.env.get("LIFEMATE_ADMIN_DB_URL");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKeys = readDictionary("SUPABASE_PUBLISHABLE_KEYS");
  const publishableKey = publishableKeys.default ??
    Deno.env.get("SUPABASE_ANON_KEY");

  if (!bootstrapDatabaseUrl || !supabaseUrl || !publishableKey) {
    throw new Error(
      "Required LifeMate Admin runtime configuration is missing.",
    );
  }

  const vaultPassword = explicitDatabaseUrl
    ? null
    : await readAdminRuntimePassword(bootstrapDatabaseUrl);
  const databaseUrl = explicitDatabaseUrl ??
    (vaultPassword
      ? buildRestrictedDatabaseUrl(
        bootstrapDatabaseUrl,
        "lifemate_admin_runtime",
        vaultPassword,
      )
      : null);
  if (!databaseUrl) {
    throw new Error(
      "Restricted LifeMate Admin database credential is missing. Refusing privileged DB fallback.",
    );
  }

  const allowedOrigins = new Set(
    (Deno.env.get("LIFEMATE_ADMIN_ALLOWED_ORIGINS") ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );

  return {
    databaseUrl,
    supabaseUrl: supabaseUrl.replace(/\/$/, ""),
    publishableKey,
    allowedOrigins,
    bootstrapAuthSubject:
      Deno.env.get("LIFEMATE_ADMIN_BOOTSTRAP_AUTH_SUBJECT")?.trim() ||
      null,
    releaseVersion:
      (Deno.env.get("LIFEMATE_ADMIN_RELEASE_VERSION") ?? "unversioned")
        .slice(0, 128),
  };
}
