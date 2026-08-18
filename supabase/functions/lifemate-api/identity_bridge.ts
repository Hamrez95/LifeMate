import {
  encryptProviderIdentitySubject,
  providerIdentityHandleDualWriteEnabled,
  rawIdentityRetirementEnabled,
  readProviderIdentityHandleKey,
} from "../_shared/provider_identity_handle_crypto.ts";
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
type AccountIdRow = { account_id: string };

type ProviderHandleEnvelope = {
  ciphertextB64: string;
  nonceB64: string;
  keyVersion: number;
};

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
  const providerHandleDualWrite = providerIdentityHandleDualWriteEnabled();
  if (providerHandleDualWrite && !dualWrite) {
    throw new Error(
      "Encrypted provider-handle dual-write requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true so the canonical token and recovery handle advance together.",
    );
  }
  const providerHandleKey = providerHandleDualWrite
    ? readProviderIdentityHandleKey()
    : null;
  const rawRetirement = rawIdentityRetirementEnabled();
  if (rawRetirement) {
    const lookupMode =
      (Deno.env.get("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE") ?? "legacy")
        .trim()
        .toLowerCase();
    if (lookupMode !== "token-only") {
      throw new Error(
        "Raw identity retirement requires LIFEMATE_IDENTITY_LINK_LOOKUP_MODE=token-only.",
      );
    }
    if (!dualWrite || !identityLinkKey) {
      throw new Error(
        "Raw identity retirement requires canonical identity-token dual-write.",
      );
    }
    if (!providerHandleDualWrite || !providerHandleKey) {
      throw new Error(
        "Raw identity retirement requires encrypted provider-handle dual-write.",
      );
    }
  }

  async function syncExternalIdentities(
    legacyAppUserId: string,
    auth: AuthIdentitySnapshot,
  ): Promise<string[]> {
    const providers = new Set<string>();

    return await sql.begin(async (transaction) => {
      const accountRows: AccountIdRow[] = await transaction`
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

      let canonicalSubjectToken: string | null = null;
      if (identityLinkKey) {
        // Canonical runtime authentication lookup. Provider-specific tokens
        // below are useful for explicit account-linking, but JWT/API identity
        // resolution must not depend on a Google/email provider subject.
        canonicalSubjectToken = await deriveIdentityLinkToken(
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

      let providerEnvelope: ProviderHandleEnvelope | null = null;
      if (providerHandleKey) {
        providerEnvelope = await encryptProviderIdentitySubject(
          providerHandleKey,
          {
            accountId,
            provider: "supabase_auth",
            issuer: "supabase",
          },
          auth.id,
        );
        await upsertProviderHandle(
          transaction,
          accountId,
          providerEnvelope,
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

        if (!rawRetirement) {
          const rows: AccountIdRow[] = await transaction`
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
        }
        providers.add(provider);
      }

      if (rawRetirement) {
        // These checks intentionally happen inside the same transaction as the
        // scrub. A missing/conflicting token or recovery handle rolls back all
        // changes and leaves the raw compatibility subject untouched.
        if (
          !identityLinkKey ||
          !canonicalSubjectToken ||
          !providerEnvelope
        ) {
          throw new Error("raw_identity_retirement_prerequisite_missing");
        }
        const readiness = await transaction`
          select
            exists(
              select 1 from identity.external_identity_tokens t
              where t.account_id=${accountId}::uuid
                and t.provider='supabase_auth'
                and t.issuer='supabase'
                and t.subject_token=${canonicalSubjectToken}
                and t.key_version=${identityLinkKey.keyVersion}
                and t.status='Active'
            ) as token_ready,
            exists(
              select 1 from identity.provider_identity_handles h
              where h.account_id=${accountId}::uuid
                and h.provider='supabase_auth'
                and h.issuer='supabase'
                and h.key_version=${providerEnvelope.keyVersion}
                and h.status='Active'
            ) as handle_ready
        `;
        if (
          readiness[0]?.token_ready !== true ||
          readiness[0]?.handle_ready !== true
        ) {
          throw new Error("raw_identity_retirement_prerequisite_missing");
        }

        const scrubbed = await transaction`
          update lifemate.app_users
             set auth_subject=null,
                 updated_at_utc=now()
           where id=${legacyAppUserId}::uuid
             and (auth_subject=${auth.id} or auth_subject is null)
          returning id
        `;
        if (!scrubbed[0]) {
          throw new ApiError(
            409,
            "raw_identity_subject_conflict",
            "The legacy identity subject does not match the authenticated account.",
          );
        }

        await transaction`
          delete from identity.external_identities
          where account_id=${accountId}::uuid
        `;
      }

      return [...providers].sort();
    });
  }

  async function upsertProviderHandle(
    transaction: any,
    accountId: string,
    envelope: ProviderHandleEnvelope,
  ): Promise<void> {
    const rows: AccountIdRow[] = await transaction`
      insert into identity.provider_identity_handles(
        account_id,provider,issuer,ciphertext_b64,nonce_b64,key_version,
        status,created_at_utc,updated_at_utc
      ) values(
        ${accountId}::uuid,'supabase_auth','supabase',
        ${envelope.ciphertextB64},${envelope.nonceB64},
        ${envelope.keyVersion},'Active',now(),now()
      )
      on conflict(account_id,provider,issuer) do update set
        ciphertext_b64=excluded.ciphertext_b64,
        nonce_b64=excluded.nonce_b64,
        key_version=excluded.key_version,
        status='Active',
        updated_at_utc=excluded.updated_at_utc
      returning account_id
    `;
    if (rows[0]?.account_id !== accountId) {
      throw new ApiError(
        409,
        "provider_identity_handle_account_conflict",
        "The encrypted provider handle belongs to another LifeMate account.",
      );
    }
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
    const rows: AccountIdRow[] = await transaction`
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
