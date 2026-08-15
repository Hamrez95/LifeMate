import postgres from "npm:postgres@3.4.7";
import { deriveIdentityLinkToken } from "../../supabase/functions/lifemate-api/identity_link_token.ts";

type BackfillMode = "dry-run" | "apply";

type CanonicalIdentityRow = {
  account_id: string;
  auth_subject: string;
  created_at_utc: Date;
  last_authenticated_at_utc: Date | null;
};

type ProviderIdentityRow = {
  account_id: string;
  provider: string;
  issuer: string;
  provider_subject: string;
  created_at_utc: Date;
  last_authenticated_at_utc: Date | null;
};

type PlannedToken = {
  accountId: string;
  provider: string;
  issuer: string;
  subjectToken: string;
  keyVersion: number;
  createdAt: Date;
  lastAuthenticatedAt: Date;
};

export type BackfillSummary = {
  mode: BackfillMode;
  canonicalAccounts: number;
  providerIdentities: number;
  plannedTokens: number;
  insertedOrRefreshed: number;
};

function requireKeyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 65535) {
    throw new Error("Identity-link key version must be an integer from 1 to 65535.");
  }
  return value;
}

function requireExternalKey(value: string): string {
  if (new TextEncoder().encode(value).byteLength < 32) {
    throw new Error("Identity-link key must contain at least 32 UTF-8 bytes.");
  }
  return value;
}

function requireMode(value: string): BackfillMode {
  if (value === "dry-run" || value === "apply") return value;
  throw new Error("Backfill mode must be dry-run or apply.");
}

function tokenKey(token: PlannedToken): string {
  return [
    token.provider,
    token.issuer,
    String(token.keyVersion),
    token.subjectToken,
  ].join("\u0000");
}

export async function backfillIdentityLinkTokens(options: {
  databaseUrl: string;
  externalKey: string;
  keyVersion: number;
  mode: BackfillMode;
}): Promise<BackfillSummary> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const externalKey = requireExternalKey(options.externalKey);
  const keyVersion = requireKeyVersion(options.keyVersion);
  const mode = requireMode(options.mode);

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });

  try {
    const tableRows = await sql<{ exists: boolean }[]>`
      select to_regclass('identity.external_identity_tokens') is not null as exists
    `;
    if (!tableRows[0]?.exists) {
      throw new Error(
        "identity.external_identity_tokens is missing; apply the reviewed migration before backfill.",
      );
    }

    const canonicalRows = await sql<CanonicalIdentityRow[]>`
      select
        a.id::text as account_id,
        lu.auth_subject,
        a.created_at_utc,
        null::timestamptz as last_authenticated_at_utc
      from identity.accounts a
      join lifemate.app_users lu on lu.id=a.legacy_app_user_id
      where a.status <> 'Deleted'
      order by a.id
    `;
    const providerRows = await sql<ProviderIdentityRow[]>`
      select
        account_id::text as account_id,
        provider,
        issuer,
        provider_subject,
        created_at_utc,
        last_authenticated_at_utc
      from identity.external_identities
      where status='Active'
      order by account_id,provider,issuer
    `;

    const planned: PlannedToken[] = [];
    for (const row of canonicalRows) {
      planned.push({
        accountId: row.account_id,
        provider: "supabase_auth",
        issuer: "supabase",
        subjectToken: await deriveIdentityLinkToken(externalKey, {
          provider: "supabase_auth",
          issuer: "supabase",
          subject: row.auth_subject,
          keyVersion,
        }),
        keyVersion,
        createdAt: row.created_at_utc,
        lastAuthenticatedAt: row.last_authenticated_at_utc ?? new Date(),
      });
    }
    for (const row of providerRows) {
      planned.push({
        accountId: row.account_id,
        provider: row.provider,
        issuer: row.issuer,
        subjectToken: await deriveIdentityLinkToken(externalKey, {
          provider: row.provider,
          issuer: row.issuer,
          subject: row.provider_subject,
          keyVersion,
        }),
        keyVersion,
        createdAt: row.created_at_utc,
        lastAuthenticatedAt: row.last_authenticated_at_utc ?? new Date(),
      });
    }

    // Detect collisions/conflicting historical links before any write. Duplicate
    // canonical/provider rows for the same Account are harmless and collapse to
    // one token; the same token across Accounts is a fail-closed migration error.
    const ownerByToken = new Map<string, string>();
    const deduped = new Map<string, PlannedToken>();
    for (const token of planned) {
      const key = tokenKey(token);
      const owner = ownerByToken.get(key);
      if (owner && owner !== token.accountId) {
        throw new Error(
          "Identity-link backfill found one external identity mapped to multiple Accounts.",
        );
      }
      ownerByToken.set(key, token.accountId);
      deduped.set(`${token.accountId}\u0000${key}`, token);
    }

    const tokens = [...deduped.values()];
    const existing = await sql<{
      account_id: string;
      provider: string;
      issuer: string;
      subject_token: string;
      key_version: number;
    }[]>`
      select
        account_id::text as account_id,
        provider,
        issuer,
        subject_token,
        key_version
      from identity.external_identity_tokens
      where key_version=${keyVersion}
    `;
    for (const row of existing) {
      const key = [
        row.provider,
        row.issuer,
        String(row.key_version),
        row.subject_token,
      ].join("\u0000");
      const plannedOwner = ownerByToken.get(key);
      if (plannedOwner && plannedOwner !== row.account_id) {
        throw new Error(
          "Identity-link backfill conflicts with an existing token owned by another Account.",
        );
      }
    }

    if (mode === "dry-run") {
      return {
        mode,
        canonicalAccounts: canonicalRows.length,
        providerIdentities: providerRows.length,
        plannedTokens: tokens.length,
        insertedOrRefreshed: 0,
      };
    }

    let insertedOrRefreshed = 0;
    await sql.begin(async (transaction) => {
      for (const token of tokens) {
        const rows: { account_id: string }[] = await transaction`
          insert into identity.external_identity_tokens(
            account_id,provider,issuer,subject_token,key_version,
            created_at_utc,last_authenticated_at_utc,status
          ) values(
            ${token.accountId}::uuid,${token.provider},${token.issuer},
            ${token.subjectToken},${token.keyVersion},${token.createdAt},
            ${token.lastAuthenticatedAt},'Active'
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
        if (rows[0]?.account_id !== token.accountId) {
          throw new Error(
            "Identity-link backfill encountered a conflicting Account during apply.",
          );
        }
        insertedOrRefreshed += 1;
      }
    });

    return {
      mode,
      canonicalAccounts: canonicalRows.length,
      providerIdentities: providerRows.length,
      plannedTokens: tokens.length,
      insertedOrRefreshed,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const mode = requireMode(
    (Deno.env.get("LIFEMATE_IDENTITY_LINK_BACKFILL_MODE") ?? "dry-run")
      .trim()
      .toLowerCase(),
  );
  if (mode === "apply") {
    const confirmation = Deno.env.get("LIFEMATE_IDENTITY_LINK_BACKFILL_CONFIRM") ??
      "";
    if (confirmation !== "BACKFILL-IDENTITY-TOKENS") {
      throw new Error(
        "Apply mode requires LIFEMATE_IDENTITY_LINK_BACKFILL_CONFIRM=BACKFILL-IDENTITY-TOKENS.",
      );
    }
  }

  const summary = await backfillIdentityLinkTokens({
    databaseUrl: Deno.env.get("LIFEMATE_IDENTITY_BACKFILL_DATABASE_URL") ?? "",
    externalKey: Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY") ?? "",
    keyVersion: Number(Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY_VERSION") ?? ""),
    mode,
  });
  // Counts only. Never print raw subjects, tokens, DB URLs or key material.
  console.log(JSON.stringify(summary));
}
