import postgres from "postgres";

export type RuntimeConfig = {
  databaseUrl: string;
  supabaseUrl: string;
  publishableKey: string;
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
  for (const candidate of [
    sources.environment,
    sources.dictionary,
    sources.vault,
  ]) {
    if (isDedicatedSecret(candidate, sources.serviceRole)) return candidate;
  }

  throw new Error(
    "A dedicated LifeMate contact hashing secret of at least 32 characters is required and must not equal the service-role credential.",
  );
}

async function readVaultSecret(databaseUrl: string): Promise<string | null> {
  const sql = postgres(databaseUrl, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    prepare: false,
  });

  try {
    const rows = await sql`
      select decrypted_secret
      from vault.decrypted_secrets
      where name = 'lifemate_contact_hashing_secret'
      limit 1
    `;
    const value = rows[0]?.decrypted_secret;
    return typeof value === "string" ? value : null;
  } finally {
    await sql.end({ timeout: 5 });
  }
}

export async function loadRuntimeConfig(): Promise<RuntimeConfig> {
  const databaseUrl = Deno.env.get("SUPABASE_DB_URL");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKeys = readKeyDictionary("SUPABASE_PUBLISHABLE_KEYS");
  const secretKeys = readKeyDictionary("SUPABASE_SECRET_KEYS");
  const publishableKey = publishableKeys.default ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!databaseUrl || !supabaseUrl || !publishableKey) {
    throw new Error("Required Supabase runtime configuration is missing.");
  }

  const environmentSecret = Deno.env.get(
    "LIFEMATE_CONTACT_HASHING_SECRET",
  );
  const dictionarySecret = secretKeys.contact_hashing;
  const needsVault = !isDedicatedSecret(environmentSecret, serviceRole) &&
    !isDedicatedSecret(dictionarySecret, serviceRole);
  const vaultSecret = needsVault ? await readVaultSecret(databaseUrl) : null;
  const contactHashingSecret = selectContactHashingSecret({
    environment: environmentSecret,
    dictionary: dictionarySecret,
    vault: vaultSecret,
    serviceRole,
    // Intentionally ignored by selectContactHashingSecret. The generic default
    // secret previously matched the service-role key in the live project.
    defaultSecret: secretKeys.default,
  });

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
    contactHashingSecret,
    releaseVersion,
  };
}
