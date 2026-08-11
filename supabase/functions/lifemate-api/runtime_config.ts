import postgres from "postgres";

export type RuntimeConfig = {
  databaseUrl: string;
  supabaseUrl: string;
  publishableKey: string;
  storageServiceKey: string;
  contactHashingSecret: string;
  releaseVersion: string;
};

export type ContactSecretSources = {
  environment?: string | null;
  dictionary?: string | null;
  vault?: string | null;
  serviceRole?: string | null;
  defaultSecret?: string | null;
};

type RuntimeVaultSecrets = {
  contactHashing: string | null;
  edgeDatabasePassword: string | null;
};

type ReleaseGlobal = typeof globalThis & {
  __LIFEMATE_RELEASE_VERSION__?: unknown;
};

export function readKeyDictionary(name: string): Record<string, string> {
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

function isDedicatedSecret(
  value: string | null | undefined,
  serviceRole: string | null | undefined,
): value is string {
  return typeof value === "string" &&
    value.length >= 32 &&
    (!serviceRole || value !== serviceRole);
}

export function selectContactHashingSecret(
  sources: ContactSecretSources,
): string {
  for (
    const candidate of [
      sources.environment,
      sources.dictionary,
      sources.vault,
    ]
  ) {
    if (isDedicatedSecret(candidate, sources.serviceRole)) return candidate;
  }

  throw new Error(
    "A dedicated LifeMate contact hashing secret of at least 32 characters is required and must not equal the service-role credential.",
  );
}

/// Reuses the platform-provided host/database/pooler suffix while replacing the
/// privileged login with a dedicated restricted role. Supabase pooler usernames
/// can be `postgres.<project-ref>`; that suffix must be preserved.
export function buildRestrictedDatabaseUrl(
  bootstrapDatabaseUrl: string,
  roleName: string,
  password: string,
): string {
  if (!roleName || !/^[a-z][a-z0-9_]{2,62}$/i.test(roleName)) {
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

async function readRuntimeVaultSecrets(
  bootstrapDatabaseUrl: string,
): Promise<RuntimeVaultSecrets> {
  const sql = postgres(bootstrapDatabaseUrl, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    prepare: false,
  });

  try {
    const rows = await sql`
      select name, decrypted_secret
      from vault.decrypted_secrets
      where name in (
        'lifemate_contact_hashing_secret',
        'lifemate_edge_runtime_password'
      )
    `;
    const values = new Map<string, string>();
    for (const row of rows) {
      if (
        typeof row.name === "string" &&
        typeof row.decrypted_secret === "string"
      ) {
        values.set(row.name, row.decrypted_secret);
      }
    }
    return {
      contactHashing: values.get("lifemate_contact_hashing_secret") ?? null,
      edgeDatabasePassword: values.get("lifemate_edge_runtime_password") ??
        null,
    };
  } finally {
    await sql.end({ timeout: 5 });
  }
}

export async function loadRuntimeConfig(): Promise<RuntimeConfig> {
  const bootstrapDatabaseUrl = Deno.env.get("SUPABASE_DB_URL");
  const explicitRuntimeDatabaseUrl = Deno.env.get("LIFEMATE_DB_URL");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKeys = readKeyDictionary("SUPABASE_PUBLISHABLE_KEYS");
  const secretKeys = readKeyDictionary("SUPABASE_SECRET_KEYS");
  const publishableKey = publishableKeys.default ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKeyName = ["SUPABASE", "SERVICE", "ROLE", "KEY"].join(
    "_",
  );
  const serviceRole = Deno.env.get(serviceRoleKeyName);

  if (
    !bootstrapDatabaseUrl || !supabaseUrl || !publishableKey || !serviceRole
  ) {
    throw new Error("Required Supabase runtime configuration is missing.");
  }

  const environmentSecret = Deno.env.get(
    "LIFEMATE_CONTACT_HASHING_SECRET",
  );
  const dictionarySecret = secretKeys.contact_hashing;
  const needsContactVault =
    !isDedicatedSecret(environmentSecret, serviceRole) &&
    !isDedicatedSecret(dictionarySecret, serviceRole);
  const needsDatabaseVault = !explicitRuntimeDatabaseUrl;
  const vaultSecrets = needsContactVault || needsDatabaseVault
    ? await readRuntimeVaultSecrets(bootstrapDatabaseUrl)
    : { contactHashing: null, edgeDatabasePassword: null };

  const contactHashingSecret = selectContactHashingSecret({
    environment: environmentSecret,
    dictionary: dictionarySecret,
    vault: vaultSecrets.contactHashing,
    serviceRole,
    // Intentionally ignored by selectContactHashingSecret. The generic default
    // secret previously matched the service-role key in the live project.
    defaultSecret: secretKeys.default,
  });

  const databaseUrl = explicitRuntimeDatabaseUrl ??
    (vaultSecrets.edgeDatabasePassword
      ? buildRestrictedDatabaseUrl(
        bootstrapDatabaseUrl,
        "lifemate_edge_runtime",
        vaultSecrets.edgeDatabasePassword,
      )
      : null);
  if (!databaseUrl) {
    throw new Error(
      "Restricted LifeMate database runtime credential is missing. Refusing to use the privileged Supabase database URL for application queries.",
    );
  }

  const globalRelease = (globalThis as ReleaseGlobal)
    .__LIFEMATE_RELEASE_VERSION__;
  const releaseVersion = (
    Deno.env.get("LIFEMATE_RELEASE_VERSION") ??
      (typeof globalRelease === "string" ? globalRelease : null) ??
      "0.8.0-internal.1-unversioned"
  ).slice(0, 128);

  return {
    databaseUrl,
    supabaseUrl,
    publishableKey,
    storageServiceKey: serviceRole,
    contactHashingSecret,
    releaseVersion,
  };
}
