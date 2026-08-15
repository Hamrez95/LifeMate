import postgres from "npm:postgres@3.4.7";
import { deriveIdentityLinkToken } from "../../supabase/functions/lifemate-api/identity_link_token.ts";

type ActiveAccountRow = {
  account_id: string;
  auth_subject: string;
};

type TokenRow = {
  account_id: string;
  subject_token: string;
};

export type IdentityRetirementReadiness = {
  keyVersion: number;
  activeAccounts: number;
  tokenizedAccounts: number;
  missingCanonicalTokens: number;
  conflictingCanonicalTokens: number;
  activeRawAuthSubjects: number;
  activeRawProviderIdentities: number;
  unmappedActiveAccounts: number;
  readyForTokenOnly: boolean;
};

function requireKeyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 65535) {
    throw new Error("Identity-link key version must be an integer from 1 to 65535.");
  }
  return value;
}

function requireKey(value: string): string {
  if (new TextEncoder().encode(value).byteLength < 32) {
    throw new Error("Identity-link key must contain at least 32 UTF-8 bytes.");
  }
  return value;
}

export async function assessIdentityRetirementReadiness(options: {
  databaseUrl: string;
  externalKey: string;
  keyVersion: number;
}): Promise<IdentityRetirementReadiness> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const externalKey = requireKey(options.externalKey);
  const keyVersion = requireKeyVersion(options.keyVersion);
  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });

  try {
    const activeAccounts = await sql<ActiveAccountRow[]>`
      select
        a.id::text as account_id,
        u.auth_subject
      from identity.accounts a
      join lifemate.app_users u on u.id=a.legacy_app_user_id
      where a.status='Active' and u.status='Active'
      order by a.id
    `;
    const tokenRows = await sql<TokenRow[]>`
      select account_id::text as account_id, subject_token
      from identity.external_identity_tokens
      where provider='supabase_auth'
        and issuer='supabase'
        and key_version=${keyVersion}
        and status='Active'
      order by account_id
    `;
    const aggregateRows = await sql<{
      active_raw_provider_identities: number;
      unmapped_active_accounts: number;
    }[]>`
      select
        (
          select count(*)::int
          from identity.external_identities
          where status='Active'
        ) as active_raw_provider_identities,
        (
          select count(*)::int
          from identity.accounts a
          left join lifemate.app_users u on u.id=a.legacy_app_user_id
          where a.status='Active'
            and (u.id is null or u.status <> 'Active')
        ) as unmapped_active_accounts
    `;

    const tokenOwners = new Map<string, string>();
    const tokensByAccount = new Map<string, Set<string>>();
    let conflictingCanonicalTokens = 0;
    for (const row of tokenRows) {
      const previousOwner = tokenOwners.get(row.subject_token);
      if (previousOwner && previousOwner !== row.account_id) {
        conflictingCanonicalTokens += 1;
      } else {
        tokenOwners.set(row.subject_token, row.account_id);
      }
      const accountTokens = tokensByAccount.get(row.account_id) ?? new Set<string>();
      accountTokens.add(row.subject_token);
      tokensByAccount.set(row.account_id, accountTokens);
    }

    let missingCanonicalTokens = 0;
    let tokenizedAccounts = 0;
    for (const row of activeAccounts) {
      const expectedToken = await deriveIdentityLinkToken(externalKey, {
        provider: "supabase_auth",
        issuer: "supabase",
        subject: row.auth_subject,
        keyVersion,
      });
      if (tokensByAccount.get(row.account_id)?.has(expectedToken)) {
        tokenizedAccounts += 1;
      } else {
        missingCanonicalTokens += 1;
      }
    }

    const aggregates = aggregateRows[0] ?? {
      active_raw_provider_identities: 0,
      unmapped_active_accounts: 0,
    };
    const unmappedActiveAccounts = Number(aggregates.unmapped_active_accounts);
    const result: IdentityRetirementReadiness = {
      keyVersion,
      activeAccounts: activeAccounts.length,
      tokenizedAccounts,
      missingCanonicalTokens,
      conflictingCanonicalTokens,
      activeRawAuthSubjects: activeAccounts.length,
      activeRawProviderIdentities: Number(
        aggregates.active_raw_provider_identities,
      ),
      unmappedActiveAccounts,
      readyForTokenOnly:
        missingCanonicalTokens === 0 &&
        conflictingCanonicalTokens === 0 &&
        unmappedActiveAccounts === 0 &&
        tokenizedAccounts === activeAccounts.length,
    };
    return result;
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const result = await assessIdentityRetirementReadiness({
    databaseUrl: Deno.env.get("LIFEMATE_IDENTITY_RETIREMENT_DATABASE_URL") ?? "",
    externalKey: Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY") ?? "",
    keyVersion: Number(Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY_VERSION") ?? ""),
  });
  // Counts only. Raw subjects, tokens, database URLs and key material are never emitted.
  console.log(JSON.stringify(result));
  if (!result.readyForTokenOnly) Deno.exit(2);
}
