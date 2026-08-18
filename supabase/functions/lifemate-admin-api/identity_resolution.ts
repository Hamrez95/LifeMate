import { type AdminSql, getAdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

const encoder = new TextEncoder();

export type AdminIdentityLookupMode = "legacy" | "prefer-token" | "token-only";
type EnvironmentReader = (name: string) => string | null | undefined;
type IdentityLinkKey = { secret: string; keyVersion: number };
type TokenLookupRow = { account_id: string; account_status: string };
type LegacyLookupRow = { account_id: string };

type ResolverOptions = {
  mode?: AdminIdentityLookupMode;
  identityLinkKey?: IdentityLinkKey;
  dualWriteEnabled?: boolean;
  readEnvironment?: EnvironmentReader;
  lookupToken?: (
    subjectToken: string,
    keyVersion: number,
  ) => Promise<TokenLookupRow[]>;
  lookupLegacy?: (providerSubject: string) => Promise<LegacyLookupRow[]>;
};

function requiredKeyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 65535) {
    throw new Error("Identity-link key version is invalid.");
  }
  return value;
}

function toHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export function readAdminIdentityLookupMode(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): AdminIdentityLookupMode {
  const raw = (
    readEnvironment("LIFEMATE_ADMIN_IDENTITY_LINK_LOOKUP_MODE") ??
      readEnvironment("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE") ??
      "legacy"
  ).trim().toLowerCase();
  if (raw === "legacy" || raw === "prefer-token" || raw === "token-only") {
    return raw;
  }
  throw new Error(
    "Admin identity lookup mode must be legacy, prefer-token, or token-only.",
  );
}

export function adminIdentityDualWriteEnabled(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): boolean {
  const raw = (readEnvironment("LIFEMATE_IDENTITY_LINK_DUAL_WRITE") ?? "")
    .trim()
    .toLowerCase();
  if (!raw || raw === "false") return false;
  if (raw === "true") return true;
  throw new Error(
    "LIFEMATE_IDENTITY_LINK_DUAL_WRITE must be either true or false.",
  );
}

export function readAdminIdentityLinkKey(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): IdentityLinkKey {
  const secret = readEnvironment("LIFEMATE_IDENTITY_LINK_KEY") ?? "";
  const keyVersionRaw =
    readEnvironment("LIFEMATE_IDENTITY_LINK_KEY_VERSION") ?? "";
  if (encoder.encode(secret).byteLength < 32) {
    throw new Error(
      "LIFEMATE_IDENTITY_LINK_KEY must be configured as an external runtime secret with at least 32 UTF-8 bytes.",
    );
  }
  if (!/^\d+$/.test(keyVersionRaw)) {
    throw new Error("LIFEMATE_IDENTITY_LINK_KEY_VERSION must be configured.");
  }
  return { secret, keyVersion: requiredKeyVersion(Number(keyVersionRaw)) };
}

export async function deriveAdminIdentityLinkToken(
  secret: string,
  providerSubject: string,
  keyVersion: number,
): Promise<string> {
  const keyBytes = encoder.encode(secret);
  const subject = providerSubject.trim();
  if (keyBytes.byteLength < 32) {
    throw new Error("Identity-link key must contain at least 32 UTF-8 bytes.");
  }
  if (!subject || subject.length > 512) {
    throw new Error("providerSubject is invalid.");
  }
  const version = requiredKeyVersion(keyVersion);
  const canonical = JSON.stringify({
    version,
    provider: "supabase_auth",
    issuer: "supabase",
    subject,
  });
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(
    await crypto.subtle.sign("HMAC", key, encoder.encode(canonical)),
  );
}

function defaultTokenLookup(sql: AdminSql) {
  return async (subjectToken: string, keyVersion: number) => {
    return await sql<TokenLookupRow[]>`
      select t.account_id::text as account_id,
             a.status as account_status
      from identity.external_identity_tokens t
      join identity.accounts a on a.id=t.account_id
      where t.provider='supabase_auth'
        and t.issuer='supabase'
        and t.subject_token=${subjectToken}
        and t.key_version=${keyVersion}
        and t.status='Active'
      limit 2
    `;
  };
}

function defaultLegacyLookup(sql: AdminSql) {
  return async (providerSubject: string) => {
    return await sql<LegacyLookupRow[]>`
      select a.id::text as account_id
      from identity.external_identities e
      join identity.accounts a on a.id=e.account_id
      where e.provider='supabase_auth'
        and e.issuer='supabase'
        and e.provider_subject=${providerSubject}
        and e.status='Active'
        and a.status='Active'
      limit 2
    `;
  };
}

export function createAdminIdentityResolver(
  databaseUrl: string,
  options: ResolverOptions = {},
) {
  const readEnvironment = options.readEnvironment ??
    ((name: string) => Deno.env.get(name));
  const mode = options.mode ?? readAdminIdentityLookupMode(readEnvironment);
  let identityLinkKey: IdentityLinkKey | null = null;

  if (mode !== "legacy") {
    const dualWrite = options.dualWriteEnabled ??
      adminIdentityDualWriteEnabled(readEnvironment);
    if (!dualWrite) {
      throw new Error(
        "Token-based Admin identity lookup requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true until protected raw-link retirement is complete.",
      );
    }
    identityLinkKey = options.identityLinkKey ??
      readAdminIdentityLinkKey(readEnvironment);
  }

  let sql: AdminSql | null = null;
  const getSql = () => sql ??= getAdminSql(databaseUrl);
  const lookupToken = options.lookupToken ??
    ((token, version) => defaultTokenLookup(getSql())(token, version));
  const lookupLegacy = options.lookupLegacy ??
    ((subject) => defaultLegacyLookup(getSql())(subject));

  async function resolveAccountId(providerSubject: string): Promise<string> {
    if (mode !== "legacy") {
      const key = identityLinkKey;
      if (!key) throw new Error("Admin identity-link key is unavailable.");
      const subjectToken = await deriveAdminIdentityLinkToken(
        key.secret,
        providerSubject,
        key.keyVersion,
      );
      const tokenRows = await lookupToken(subjectToken, key.keyVersion);
      if (tokenRows.length > 1) {
        throw new ApiError(
          409,
          "identity_token_ambiguous",
          "The LifeMate identity mapping is ambiguous.",
        );
      }
      const tokenRow = tokenRows[0];
      if (tokenRow) {
        if (tokenRow.account_status !== "Active") {
          throw new ApiError(
            403,
            "lifemate_account_required",
            "An active LifeMate account is required for Command Center access.",
          );
        }
        return tokenRow.account_id;
      }
      if (mode === "token-only") {
        throw new ApiError(
          403,
          "lifemate_account_required",
          "An active LifeMate account is required for Command Center access.",
        );
      }
    }

    const legacyRows = await lookupLegacy(providerSubject);
    if (legacyRows.length !== 1) {
      throw new ApiError(
        legacyRows.length > 1 ? 409 : 403,
        legacyRows.length > 1
          ? "identity_legacy_ambiguous"
          : "lifemate_account_required",
        legacyRows.length > 1
          ? "The LifeMate identity mapping is ambiguous."
          : "An active LifeMate account is required for Command Center access.",
      );
    }
    return legacyRows[0].account_id;
  }

  return { mode, resolveAccountId };
}
