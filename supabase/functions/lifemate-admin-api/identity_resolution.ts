import { type AdminSql, getAdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

const encoder = new TextEncoder();

export type AdminIdentityLookupMode = "legacy" | "prefer-token" | "token-only";
type EnvironmentReader = (name: string) => string | null | undefined;
type IdentityLinkKey = { secret: string; keyVersion: number };
type IdentityLinkKeySet = {
  active: IdentityLinkKey;
  previous: IdentityLinkKey | null;
};
type TokenLookupRow = {
  account_id: string;
  account_status: string;
  key_version?: number;
};
type LegacyLookupRow = { account_id: string };

type ResolverOptions = {
  mode?: AdminIdentityLookupMode;
  identityLinkKey?: IdentityLinkKey;
  previousIdentityLinkKey?: IdentityLinkKey | null;
  dualWriteEnabled?: boolean;
  readEnvironment?: EnvironmentReader;
  lookupToken?: (
    subjectToken: string,
    keyVersion: number,
  ) => Promise<TokenLookupRow[]>;
  lookupRotationTokens?: (
    activeToken: string,
    activeVersion: number,
    previousToken: string,
    previousVersion: number,
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

function readConfiguredKey(
  readEnvironment: EnvironmentReader,
  secretName: string,
  versionName: string,
): IdentityLinkKey {
  const secret = readEnvironment(secretName) ?? "";
  const keyVersionRaw = readEnvironment(versionName) ?? "";
  if (encoder.encode(secret).byteLength < 32) {
    throw new Error(
      `${secretName} must be configured as an external runtime secret with at least 32 UTF-8 bytes.`,
    );
  }
  if (!/^\d+$/.test(keyVersionRaw)) {
    throw new Error(`${versionName} must be configured.`);
  }
  return { secret, keyVersion: requiredKeyVersion(Number(keyVersionRaw)) };
}

export function readAdminIdentityLinkKey(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): IdentityLinkKey {
  return readConfiguredKey(
    readEnvironment,
    "LIFEMATE_IDENTITY_LINK_KEY",
    "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
  );
}

export function readAdminIdentityLinkKeySet(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): IdentityLinkKeySet {
  const active = readAdminIdentityLinkKey(readEnvironment);
  const previousSecret =
    readEnvironment("LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY") ?? "";
  const previousVersion =
    readEnvironment("LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION") ?? "";
  const hasPreviousSecret = previousSecret.length > 0;
  const hasPreviousVersion = previousVersion.trim().length > 0;
  if (hasPreviousSecret !== hasPreviousVersion) {
    throw new Error(
      "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY and LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION must be configured together.",
    );
  }
  if (!hasPreviousSecret) return { active, previous: null };

  const previous = readConfiguredKey(
    readEnvironment,
    "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY",
    "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION",
  );
  if (previous.keyVersion === active.keyVersion) {
    throw new Error(
      "Previous identity-link key version must differ from the active key version.",
    );
  }
  return { active, previous };
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
             a.status as account_status,
             t.key_version as key_version
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

function defaultRotationTokenLookup(sql: AdminSql) {
  return async (
    activeToken: string,
    activeVersion: number,
    previousToken: string,
    previousVersion: number,
  ) => {
    return await sql<TokenLookupRow[]>`
      select t.account_id::text as account_id,
             a.status as account_status,
             t.key_version as key_version
      from identity.external_identity_tokens t
      join identity.accounts a on a.id=t.account_id
      where t.provider='supabase_auth'
        and t.issuer='supabase'
        and t.status='Active'
        and (
          (t.subject_token=${activeToken} and t.key_version=${activeVersion})
          or
          (t.subject_token=${previousToken} and t.key_version=${previousVersion})
        )
      limit 4
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
  let identityLinkKeys: IdentityLinkKeySet | null = null;

  if (mode !== "legacy") {
    const dualWrite = options.dualWriteEnabled ??
      adminIdentityDualWriteEnabled(readEnvironment);
    if (!dualWrite) {
      throw new Error(
        "Token-based Admin identity lookup requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true until protected raw-link retirement is complete.",
      );
    }
    if (options.identityLinkKey) {
      identityLinkKeys = {
        active: options.identityLinkKey,
        previous: options.previousIdentityLinkKey ?? null,
      };
    } else {
      identityLinkKeys = readAdminIdentityLinkKeySet(readEnvironment);
      if (options.previousIdentityLinkKey !== undefined) {
        identityLinkKeys.previous = options.previousIdentityLinkKey;
      }
    }
    if (
      identityLinkKeys.previous &&
      identityLinkKeys.previous.keyVersion ===
        identityLinkKeys.active.keyVersion
    ) {
      throw new Error(
        "Previous identity-link key version must differ from the active key version.",
      );
    }
  }

  let sql: AdminSql | null = null;
  const getSql = () => sql ??= getAdminSql(databaseUrl);
  const lookupToken = options.lookupToken ??
    ((token, version) => defaultTokenLookup(getSql())(token, version));
  const lookupRotationTokens = options.lookupRotationTokens ??
    ((activeToken, activeVersion, previousToken, previousVersion) =>
      defaultRotationTokenLookup(getSql())(
        activeToken,
        activeVersion,
        previousToken,
        previousVersion,
      ));
  const lookupLegacy = options.lookupLegacy ??
    ((subject) => defaultLegacyLookup(getSql())(subject));

  async function resolveAccountId(providerSubject: string): Promise<string> {
    if (mode !== "legacy") {
      const keys = identityLinkKeys;
      if (!keys) throw new Error("Admin identity-link key is unavailable.");

      let active: TokenLookupRow | null;
      let previous: TokenLookupRow | null = null;
      if (keys.previous && options.lookupToken == null) {
        const activeToken = await deriveTokenForKey(providerSubject, keys.active);
        const previousToken = await deriveTokenForKey(
          providerSubject,
          keys.previous,
        );
        const rows = await lookupRotationTokens(
          activeToken,
          keys.active.keyVersion,
          previousToken,
          keys.previous.keyVersion,
        );
        active = requireUsableTokenRow(
          rows.filter((row) => Number(row.key_version) === keys.active.keyVersion),
        );
        previous = requireUsableTokenRow(
          rows.filter((row) =>
            Number(row.key_version) === keys.previous!.keyVersion
          ),
        );
      } else {
        active = requireUsableTokenRow(
          await lookupForKey(providerSubject, keys.active),
        );
        previous = keys.previous
          ? requireUsableTokenRow(
            await lookupForKey(providerSubject, keys.previous),
          )
          : null;
      }

      if (active && previous && active.account_id !== previous.account_id) {
        throw new ApiError(
          409,
          "identity_token_rotation_conflict",
          "The LifeMate identity mapping is inconsistent during key rotation.",
        );
      }
      const selected = active ?? previous;
      if (selected) return selected.account_id;

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

  async function deriveTokenForKey(
    providerSubject: string,
    key: IdentityLinkKey,
  ): Promise<string> {
    return await deriveAdminIdentityLinkToken(
      key.secret,
      providerSubject,
      key.keyVersion,
    );
  }

  async function lookupForKey(
    providerSubject: string,
    key: IdentityLinkKey,
  ): Promise<TokenLookupRow[]> {
    return await lookupToken(
      await deriveTokenForKey(providerSubject, key),
      key.keyVersion,
    );
  }

  function requireUsableTokenRow(
    rows: TokenLookupRow[],
  ): TokenLookupRow | null {
    if (rows.length > 1) {
      throw new ApiError(
        409,
        "identity_token_ambiguous",
        "The LifeMate identity mapping is ambiguous.",
      );
    }
    const row = rows[0];
    if (!row) return null;
    if (row.account_status !== "Active") {
      throw new ApiError(
        403,
        "lifemate_account_required",
        "An active LifeMate account is required for Command Center access.",
      );
    }
    return row;
  }

  return { mode, resolveAccountId };
}
