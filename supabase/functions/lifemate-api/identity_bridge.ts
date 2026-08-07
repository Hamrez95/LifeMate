import { getLifeMateSql } from "./database_client.ts";

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

  async function syncExternalIdentities(
    accountId: string,
    auth: AuthIdentitySnapshot,
  ): Promise<string[]> {
    const providers = new Set<string>();

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

      const rows = await sql`
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
        throw new Error("external_identity_account_conflict");
      }
      providers.add(provider);
    }

    return [...providers].sort();
  }

  return { syncExternalIdentities };
}
