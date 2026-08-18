import { getLifeMateSql } from "./database_client.ts";
import { identityLinkDualWriteEnabled } from "./identity_bridge.ts";
import {
  deriveIdentityLinkToken,
  type IdentityLinkKey,
  type IdentityLinkKeySet,
  readIdentityLinkKeySetFromEnvironment,
} from "./identity_link_token.ts";
import { ApiError } from "./validation.ts";

export type IdentityLookupMode = "legacy" | "prefer-token" | "token-only";

type EnvironmentReader = (name: string) => string | null | undefined;
type IdentitySql = ReturnType<typeof getLifeMateSql>;

export type ResolvableAuthUser = {
  id: string;
  email: string | null;
  phone: string | null;
  userMetadata: Record<string, unknown>;
};

export type ResolvedAppIdentity<
  TAuth extends ResolvableAuthUser = ResolvableAuthUser,
> = {
  auth: TAuth;
  appUserId: string;
};

type TokenLookupRow = {
  account_id: string;
  account_status: string;
  app_user_id: string | null;
  app_user_status: string | null;
};

type TokenCandidate = {
  subjectToken: string;
  keyVersion: number;
};

type LegacyLookupRow = { app_user_id: string };

export function readIdentityLookupMode(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): IdentityLookupMode {
  const raw =
    (readEnvironment("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE") ?? "legacy")
      .trim()
      .toLowerCase();
  if (raw === "legacy" || raw === "prefer-token" || raw === "token-only") {
    return raw;
  }
  throw new Error(
    "LIFEMATE_IDENTITY_LINK_LOOKUP_MODE must be legacy, prefer-token, or token-only.",
  );
}

export function createIdentityResolver(
  databaseUrl: string,
  options: {
    mode?: IdentityLookupMode;
    identityLinkKey?: IdentityLinkKey;
    previousIdentityLinkKey?: IdentityLinkKey | null;
    dualWriteEnabled?: boolean;
    readEnvironment?: EnvironmentReader;
  } = {},
) {
  const readEnvironment = options.readEnvironment ??
    ((name) => Deno.env.get(name));
  const lookupMode = options.mode ?? readIdentityLookupMode(readEnvironment);

  let identityLinkKeys: IdentityLinkKeySet | null = null;
  if (lookupMode !== "legacy") {
    const dualWrite = options.dualWriteEnabled ??
      identityLinkDualWriteEnabled(readEnvironment);
    if (!dualWrite) {
      throw new Error(
        "Token-based identity lookup requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true so newly bootstrapped identities cannot be stranded without a canonical token.",
      );
    }
    if (options.identityLinkKey) {
      identityLinkKeys = {
        active: options.identityLinkKey,
        previous: options.previousIdentityLinkKey ?? null,
      };
    } else {
      identityLinkKeys = readIdentityLinkKeySetFromEnvironment(readEnvironment);
      if (options.previousIdentityLinkKey !== undefined) {
        identityLinkKeys.previous = options.previousIdentityLinkKey;
      }
    }
    if (
      identityLinkKeys.previous &&
      identityLinkKeys.previous.keyVersion === identityLinkKeys.active.keyVersion
    ) {
      throw new Error(
        "Previous identity-link key version must differ from the active key version.",
      );
    }
  }

  // Keep configuration validation independent from the PostgreSQL client so
  // malformed token modes fail deterministically before any connection/env
  // handling. The same bounded client is then reused for all lookups.
  let sqlClient: IdentitySql | null = null;
  function sql(): IdentitySql {
    sqlClient ??= getLifeMateSql(databaseUrl);
    return sqlClient;
  }

  async function requireIdentity<TAuth extends ResolvableAuthUser>(
    auth: TAuth,
  ): Promise<ResolvedAppIdentity<TAuth>> {
    if (lookupMode === "legacy") {
      return await requireLegacyIdentity(auth);
    }

    const keys = identityLinkKeys;
    if (!keys) {
      throw new Error("Token-based identity lookup key is unavailable.");
    }

    const appUserId = await resolveTokenAppUserId(auth.id, keys);
    if (appUserId) return { auth, appUserId };

    if (lookupMode === "token-only") {
      throw new ApiError(404, "not_onboarded", "Bootstrap is required.");
    }

    // Bounded migration compatibility only. Once the protected backfill and
    // live token lookup evidence are complete, production advances to
    // token-only and this raw-subject fallback can be retired separately.
    return await requireLegacyIdentity(auth);
  }

  async function resolveTokenAppUserId(
    authSubject: string,
    keys: IdentityLinkKeySet,
  ): Promise<string | null> {
    const active = await tokenCandidate(keys.active, authSubject);
    if (!keys.previous) {
      const activeRow = requireUsableTokenRow(
        await lookupToken(sql(), active),
      );
      return activeRow?.app_user_id ?? null;
    }

    const previous = await tokenCandidate(keys.previous, authSubject);
    return await sql().begin(async (transaction: any) => {
      // Read both candidates inside one snapshot. A valid active token does not
      // mask a conflicting previous token during overlap; cross-key ambiguity is
      // a security error and must fail closed rather than selecting one mapping.
      const activeRow = requireUsableTokenRow(
        await lookupToken(transaction, active),
      );
      const previousRow = requireUsableTokenRow(
        await lookupToken(transaction, previous),
      );

      if (
        activeRow &&
        previousRow &&
        activeRow.account_id !== previousRow.account_id
      ) {
        throw new ApiError(
          409,
          "identity_token_rotation_conflict",
          "The LifeMate identity mapping is inconsistent during key rotation.",
        );
      }

      const selected = activeRow ?? previousRow;
      if (!selected?.app_user_id) return null;

      if (!activeRow) {
        // Lazy convergence is atomic with validation of the previous mapping.
        // Keep the previous token active for rolling-deploy overlap; removing it
        // is a separate evidence-gated operation after readiness reaches zero.
        await upsertActiveToken(
          transaction,
          selected.account_id,
          active,
        );
      }
      return selected.app_user_id;
    });
  }

  async function tokenCandidate(
    key: IdentityLinkKey,
    authSubject: string,
  ): Promise<TokenCandidate> {
    return {
      subjectToken: await deriveIdentityLinkToken(key.secret, {
        provider: "supabase_auth",
        issuer: "supabase",
        subject: authSubject,
        keyVersion: key.keyVersion,
      }),
      keyVersion: key.keyVersion,
    };
  }

  async function lookupToken(
    connection: any,
    candidate: TokenCandidate,
  ): Promise<TokenLookupRow[]> {
    const rows: TokenLookupRow[] = await connection`
      select
        t.account_id::text as account_id,
        a.status as account_status,
        a.legacy_app_user_id::text as app_user_id,
        u.status as app_user_status
      from identity.external_identity_tokens t
      join identity.accounts a on a.id=t.account_id
      left join lifemate.app_users u on u.id=a.legacy_app_user_id
      where t.provider='supabase_auth'
        and t.issuer='supabase'
        and t.subject_token=${candidate.subjectToken}
        and t.key_version=${candidate.keyVersion}
        and t.status='Active'
      limit 2
    `;
    return rows;
  }

  function requireUsableTokenRow(
    tokenRows: TokenLookupRow[],
  ): TokenLookupRow | null {
    if (tokenRows.length > 1) {
      throw new ApiError(
        409,
        "identity_token_ambiguous",
        "The LifeMate identity mapping is ambiguous.",
      );
    }
    const tokenRow = tokenRows[0];
    if (!tokenRow) return null;
    if (
      tokenRow.account_status !== "Active" ||
      !tokenRow.app_user_id ||
      tokenRow.app_user_status !== "Active"
    ) {
      throw new ApiError(
        409,
        "identity_account_mapping_missing",
        "The LifeMate account mapping is unavailable.",
      );
    }
    return tokenRow;
  }

  async function upsertActiveToken(
    transaction: any,
    accountId: string,
    candidate: TokenCandidate,
  ): Promise<void> {
    const rows: { account_id: string }[] = await transaction`
      insert into identity.external_identity_tokens(
        account_id,provider,issuer,subject_token,key_version,
        created_at_utc,last_authenticated_at_utc,status
      ) values(
        ${accountId}::uuid,'supabase_auth','supabase',
        ${candidate.subjectToken},${candidate.keyVersion},now(),now(),'Active'
      )
      on conflict(provider,issuer,key_version,subject_token) do update set
        last_authenticated_at_utc=greatest(
          identity.external_identity_tokens.last_authenticated_at_utc,
          excluded.last_authenticated_at_utc
        ),
        status='Active'
      where identity.external_identity_tokens.account_id=excluded.account_id
      returning account_id::text as account_id
    `;
    if (rows[0]?.account_id !== accountId) {
      throw new ApiError(
        409,
        "identity_token_rotation_conflict",
        "The LifeMate identity mapping is inconsistent during key rotation.",
      );
    }
  }

  async function requireLegacyIdentity<TAuth extends ResolvableAuthUser>(
    auth: TAuth,
  ): Promise<ResolvedAppIdentity<TAuth>> {
    const database = sql();
    const rows = await database<LegacyLookupRow[]>`
      select id::text as app_user_id
      from lifemate.app_users
      where auth_subject=${auth.id} and status='Active'
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(404, "not_onboarded", "Bootstrap is required.");
    }
    return { auth, appUserId: rows[0].app_user_id };
  }

  return { lookupMode, requireIdentity };
}
