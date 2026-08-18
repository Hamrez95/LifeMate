import {
  decryptProviderIdentitySubject,
  providerIdentityHandleDualWriteEnabled,
  type ProviderIdentityHandleEnvelope,
  rawIdentityRetirementEnabled,
  readProviderIdentityHandleKey,
} from "../_shared/provider_identity_handle_crypto.ts";

type EnvironmentReader = (name: string) => string | null | undefined;
type HandleRow = {
  ciphertext_b64: string;
  nonce_b64: string;
  key_version: number | string;
};
type LegacyRow = { auth_subject: string | null };

type ResolverOptions = {
  readEnvironment?: EnvironmentReader;
  lookupHandle?: (accountId: string) => Promise<HandleRow[]>;
  lookupLegacy?: (accountId: string) => Promise<LegacyRow[]>;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function createProviderAuthSubjectResolver(
  sql: any,
  options: ResolverOptions = {},
) {
  const readEnvironment = options.readEnvironment ??
    ((name: string) => Deno.env.get(name));
  const handleEnabled = providerIdentityHandleDualWriteEnabled(readEnvironment);
  const rawRetirement = rawIdentityRetirementEnabled(readEnvironment);
  if (rawRetirement && !handleEnabled) {
    throw new Error(
      "Raw identity retirement requires LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE=true so provider-control operations cannot lose their recovery handle.",
    );
  }
  const providerHandleKey = handleEnabled
    ? readProviderIdentityHandleKey(readEnvironment)
    : null;

  const lookupHandle = options.lookupHandle ??
    (async (accountId: string): Promise<HandleRow[]> => {
      const rows = await sql`
        select ciphertext_b64,nonce_b64,key_version
        from identity.provider_identity_handles
        where account_id=${accountId}::uuid
          and provider='supabase_auth'
          and issuer='supabase'
          and status='Active'
        limit 2
      `;
      return rows as HandleRow[];
    });
  const lookupLegacy = options.lookupLegacy ??
    (async (accountId: string): Promise<LegacyRow[]> => {
      const rows = await sql`
        select u.auth_subject
        from identity.accounts a
        join lifemate.app_users u
          on u.id=coalesce(a.legacy_app_user_id,a.id)
        where a.id=${accountId}::uuid
          and u.status <> 'Deleted'
        limit 1
      `;
      return rows as LegacyRow[];
    });

  async function resolve(accountId: string): Promise<string | null> {
    if (!uuidPattern.test(accountId)) {
      throw new Error("provider_handle_account_invalid");
    }

    if (providerHandleKey) {
      const rows = await lookupHandle(accountId);
      if (rows.length > 1) throw new Error("provider_handle_ambiguous");
      const row = rows[0];
      if (row) {
        const envelope: ProviderIdentityHandleEnvelope = {
          ciphertextB64: row.ciphertext_b64,
          nonceB64: row.nonce_b64,
          keyVersion: Number(row.key_version),
        };
        let subject: string;
        try {
          subject = await decryptProviderIdentitySubject(
            providerHandleKey,
            {
              accountId,
              provider: "supabase_auth",
              issuer: "supabase",
            },
            envelope,
          );
        } catch {
          throw new Error("provider_handle_decrypt_failed");
        }
        if (!uuidPattern.test(subject)) {
          throw new Error("provider_handle_subject_invalid");
        }
        return subject;
      }
      if (rawRetirement) throw new Error("provider_handle_missing");
    }

    const legacyRows = await lookupLegacy(accountId);
    const subject = legacyRows[0]?.auth_subject;
    return typeof subject === "string" && uuidPattern.test(subject)
      ? subject
      : null;
  }

  return { handleEnabled, rawRetirement, resolve };
}
