import { getLifeMateSql } from "./database_client.ts";
import { identityLinkDualWriteEnabled } from "./identity_bridge.ts";
import {
  deriveIdentityLinkToken,
  readIdentityLinkKeyFromEnvironment,
} from "./identity_link_token.ts";
import { ApiError } from "./validation.ts";

export type IdentityLookupMode = "legacy" | "prefer-token" | "token-only";

type EnvironmentReader = (name: string) => string | null | undefined;
type IdentityLinkKey = { secret: string; keyVersion: number };

export type ResolvableAuthUser = {
  id: string;
  email: string | null;
  phone: string | null;
  userMetadata: Record<string, unknown>;
};

export type ResolvedAppIdentity<TAuth extends ResolvableAuthUser = ResolvableAuthUser> = {
  auth: TAuth;
  appUserId: string;
};

type TokenLookupRow = {
  account_id: string;
  account_status: string;
  app_user_id: string | null;
  app_user_status: string | null;
};

type LegacyLookupRow = { app_user_id: string };

export function readIdentityLookupMode(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): IdentityLookupMode {
  const raw = (readEnvironment("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE") ?? "legacy")
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
    dualWriteEnabled?: boolean;
    readEnvironment?: EnvironmentReader;
  } = {},
) {
  const sql = getLifeMateSql(databaseUrl);
  const readEnvironment = options.readEnvironment ?? ((name) => Deno.env.get(name));
  const lookupMode = options.mode ?? readIdentityLookupMode(readEnvironment);

  let identityLinkKey: IdentityLinkKey | null = null;
  if (lookupMode !== "legacy") {
    const dualWrite = options.dualWriteEnabled ??
      identityLinkDualWriteEnabled(readEnvironment);
    if (!dualWrite) {
      throw new Error(
        "Token-based identity lookup requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true so newly bootstrapped identities cannot be stranded without a canonical token.",
      );
    }
    identityLinkKey = options.identityLinkKey ??
      readIdentityLinkKeyFromEnvironment(readEnvironment);
  }

  async function requireIdentity<TAuth extends ResolvableAuthUser>(
    auth: TAuth,
  ): Promise<ResolvedAppIdentity<TAuth>> {
    if (lookupMode === "legacy") {
      return await requireLegacyIdentity(auth);
    }

    const key = identityLinkKey;
    if (!key) {
      throw new Error("Token-based identity lookup key is unavailable.");
    }
    const subjectToken = await deriveIdentityLinkToken(key.secret, {
      provider: "supabase_auth",
      issuer: "supabase",
      subject: auth.id,
      keyVersion: key.keyVersion,
    });

    const tokenRows = await sql<TokenLookupRow[]>`
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
        and t.subject_token=${subjectToken}
        and t.key_version=${key.keyVersion}
        and t.status='Active'
      limit 2
    `;

    if (tokenRows.length > 1) {
      throw new ApiError(
        409,
        "identity_token_ambiguous",
        "The LifeMate identity mapping is ambiguous.",
      );
    }
    const tokenRow = tokenRows[0];
    if (tokenRow) {
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
      return { auth, appUserId: tokenRow.app_user_id };
    }

    if (lookupMode === "token-only") {
      throw new ApiError(404, "not_onboarded", "Bootstrap is required.");
    }

    // Bounded migration compatibility only. Once the protected backfill and
    // live token lookup evidence are complete, production advances to
    // token-only and this raw-subject fallback can be retired separately.
    return await requireLegacyIdentity(auth);
  }

  async function requireLegacyIdentity<TAuth extends ResolvableAuthUser>(
    auth: TAuth,
  ): Promise<ResolvedAppIdentity<TAuth>> {
    const rows = await sql<LegacyLookupRow[]>`
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
