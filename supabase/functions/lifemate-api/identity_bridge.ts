import { getLifeMateSql } from "./database_client.ts";
import {
  deriveIdentityLinkToken,
  readIdentityLinkKeyFromEnvironment,
} from "./identity_link_token.ts";
import { ApiError } from "./validation.ts";

export type ProviderIdentity = {
  provider?: unknown;
  identity_data?: unknown;
  last_sign_in_at?: unknown;
  created_at?: unknown;
};

export type AuthIdentitySnapshot = {
  id: string;
  identities: ProviderIdentity[];
};

type EnvironmentReader = (name: string) => string | null | undefined;

export function identityLinkDualWriteEnabled(
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

function providerIssuer(provider: string): string {
  switch (provider) {
    case "google":
      return "https://accounts.google.com";
    case "phone":
    case "email":
      return "supabase";
    default:
      return `supabase:${provider}`;
  }
}

function providerSubject(identity: ProviderIdentity): string | null {
  const data = identity.identity_data;
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const sub = (data as Record<string, unknown>).sub;
  if (typeof sub !== "string") return null;
  const normalized = sub.trim();
  return normalized.length > 0 && normalized.length <= 512 ? normalized : null;
}

export function createIdentityBridge(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const dualWrite = identityLinkDualWriteEnabled();
  const identityLinkKey = dualWrite
    ? readIdentityLinkKeyFromEnvironment()
    : null;

  async function syncExternalIdentities(
    legacyAppUserId: string,
    auth: AuthIdentitySnapshot,
  ): Promise<string[]> {
    const providers = new Set<string>();

    return await sql.begin(async (transaction) => {
      const accountRows = await transaction`
        select identity.account_id_for_legacy_app_user(
          ${legacyAppUserId}::uuid
        ) as account_id
      `;
      const accountId = accountRows[0]?.account_id;
      if (typeof accountId !== "string" || accountId.length === 0) {
        throw new ApiError(
          409,
          "identity_account_mapping_missing",
          "The LifeMate account mapping is unavailable.",
        );
      }

      if (identityLinkKey) {
        // Canonical runtime authentication lookup. Provider-specific tokens
        // below are useful for explicit account-linking, but JWT/API identity
        // resolution must not depend on a Google/email provider subject.
        const canonicalSubjectToken = await deriveIdentityLinkToken(
          identityLinkKey.secret,
          {
            provider: "supabase_auth",
            issuer: "supabase",
            subject: auth.id,
            keyVersion: identityLinkKey.keyVersion,
          },
        );
        await upsertIdentityToken(
          transaction,
          accountId,
          "supabase_auth",
          "supabase",
          canonicalSubjectToken,
          identityLinkKey.keyVersion,
          new Date(),
          new Date(),
        );
      }

      for (const identity of auth.identities ?? []) {
        const provider = typeof identity.provider === "string"
          ? identity.provider.trim().toLowerCase()
          : "";
        const subject = providerSubject(identity);
        if (!provider || provider.length > 80 || !subject) continue;

        const issuer = providerIssuer(provider);
        const lastAuthenticatedAt = typeof identity.last_sign_in_at === "string"
          ? new Date(identity.last_sign_in_at)
          : new Date();
        const createdAt = typeof identity.created_at === "string"
          ? new Date(identity.created_at)
          : new Date();

        if (identityLinkKey) {
          const subjectToken = await deriveIdentityLinkToken(
            identityLinkKey.secret,
            {
              provider,
              issuer,
              subject,
              keyVersion: identityLinkKey.keyVersion,
            },
          );
          await upsertIdentityToken(
            transaction,
            accountId,
            provider,
            issuer,
            subjectToken,
            identityLinkKey.keyVersion,
            createdAt,
            lastAuthenticatedAt,
          );
        }

        const rows = await transaction`
          insert into identity.external_identities(
            account_id,provider,provider_subject,issuer,created_at_utc,
            last_authenticated_at_utc,status
          ) values(
            ${accountId}::uuid,${provider},${subject},${issuer},${createdAt},
            ${lastAuthenticatedAt},'Active'
          )
          on conflict(provider,issuer,provider_subject) do update set
            last_authenticated_at_utc=greatest(
              identity.external_identities.last_authenticated_at_utc,
              excluded.last_authenticated_at_utc
            ),
            status='Active'
          where identity.external_identities.account_id=excluded.account_id
          returning account_id
        `;
        if (rows[0]?.account_id !== accountId) {
          throw new ApiError(
            409,
            "external_identity_account_conflict",
            "This external identity is already linked to another LifeMate account.",
          );
        }
        providers.add(provider);
      }

      return [...providers].sort();
    });
  }

  async function upsertIdentityToken(
    transaction: any,
    accountId: string,
    provider: string,
    issuer: string,
    subjectToken: string,
    keyVersion: number,
    createdAt: Date,
    lastAuthenticatedAt: Date,
  ): Promise<void> {
    const rows = await transaction`
      insert into identity.external_identity_tokens(
        account_id,provider,issuer,subject_token,key_version,
        created_at_utc,last_authenticated_at_utc,status
      ) values(
        ${accountId}::uuid,${provider},${issuer},${subjectToken},
        ${keyVersion},${createdAt},${lastAuthenticatedAt},'Active'
      )
      on conflict(provider,issuer,key_version,subject_token) do update set
        last_authenticated_at_utc=greatest(
          identity.external_identity_tokens.last_authenticated_at_utc,
          excluded.last_authenticated_at_utc
        ),
        status='Active'
      where identity.external_identity_tokens.account_id=excluded.account_id
      returning account_id
    `;
    if (rows[0]?.account_id !== accountId) {
      throw new ApiError(
        409,
        "external_identity_token_account_conflict",
        "This external identity is already linked to another LifeMate account.",
      );
    }
  }

  return { syncExternalIdentities };
}
