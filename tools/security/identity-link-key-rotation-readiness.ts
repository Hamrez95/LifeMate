import postgres from "npm:postgres@3.4.7";

export type IdentityLinkRotationReadiness = {
  activeVersion: number;
  activeAccounts: number;
  currentVersionReadyAccounts: number;
  missingActiveVersionTokens: number;
  multipleActiveVersionTokens: number;
  unmappedActiveAccounts: number;
  readyForPreviousKeyRemoval: boolean;
};

function requireKeyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 65535) {
    throw new Error(
      "Active identity-link key version must be an integer from 1 to 65535.",
    );
  }
  return value;
}

export async function assessIdentityLinkRotationReadiness(options: {
  databaseUrl: string;
  activeVersion: number;
}): Promise<IdentityLinkRotationReadiness> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const activeVersion = requireKeyVersion(options.activeVersion);
  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });

  try {
    const rows = await sql<{
      active_accounts: number;
      current_version_ready_accounts: number;
      missing_active_version_tokens: number;
      multiple_active_version_tokens: number;
      unmapped_active_accounts: number;
    }[]>`
      with active_accounts as (
        select a.id
        from identity.accounts a
        join lifemate.app_users u on u.id=a.legacy_app_user_id
        where a.status='Active' and u.status='Active'
      ),
      current_tokens as (
        select t.account_id,count(*)::int as token_count
        from identity.external_identity_tokens t
        join active_accounts a on a.id=t.account_id
        where t.provider='supabase_auth'
          and t.issuer='supabase'
          and t.key_version=${activeVersion}
          and t.status='Active'
        group by t.account_id
      )
      select
        (select count(*)::int from active_accounts) as active_accounts,
        (
          select count(*)::int
          from active_accounts a
          join current_tokens t on t.account_id=a.id
          where t.token_count=1
        ) as current_version_ready_accounts,
        (
          select count(*)::int
          from active_accounts a
          left join current_tokens t on t.account_id=a.id
          where t.account_id is null
        ) as missing_active_version_tokens,
        (
          select count(*)::int
          from current_tokens
          where token_count > 1
        ) as multiple_active_version_tokens,
        (
          select count(*)::int
          from identity.accounts a
          left join lifemate.app_users u on u.id=a.legacy_app_user_id
          where a.status='Active'
            and (u.id is null or u.status <> 'Active')
        ) as unmapped_active_accounts
    `;

    const row = rows[0] ?? {
      active_accounts: 0,
      current_version_ready_accounts: 0,
      missing_active_version_tokens: 0,
      multiple_active_version_tokens: 0,
      unmapped_active_accounts: 0,
    };
    const activeAccounts = Number(row.active_accounts);
    const currentVersionReadyAccounts = Number(
      row.current_version_ready_accounts,
    );
    const missingActiveVersionTokens = Number(
      row.missing_active_version_tokens,
    );
    const multipleActiveVersionTokens = Number(
      row.multiple_active_version_tokens,
    );
    const unmappedActiveAccounts = Number(row.unmapped_active_accounts);

    return {
      activeVersion,
      activeAccounts,
      currentVersionReadyAccounts,
      missingActiveVersionTokens,
      multipleActiveVersionTokens,
      unmappedActiveAccounts,
      readyForPreviousKeyRemoval: activeAccounts > 0 &&
        currentVersionReadyAccounts === activeAccounts &&
        missingActiveVersionTokens === 0 &&
        multipleActiveVersionTokens === 0 &&
        unmappedActiveAccounts === 0,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const result = await assessIdentityLinkRotationReadiness({
    databaseUrl: Deno.env.get("LIFEMATE_IDENTITY_ROTATION_DATABASE_URL") ?? "",
    activeVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY_VERSION") ?? "",
    ),
  });
  // Counts/version only. Subjects, token digests, DB URLs and key material are omitted.
  console.log(JSON.stringify(result));
  if (!result.readyForPreviousKeyRemoval) Deno.exit(2);
}
