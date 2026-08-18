import postgres from "npm:postgres@3.4.7";
import {
  hashContactPoint,
  normalizeContactPoint,
  type ContactEncryptionKey,
  type ContactPointKind,
} from "../../supabase/functions/_shared/contact_point_crypto.ts";
import { createContactPointWriter } from "../../supabase/functions/lifemate-api/contact_points.ts";

type BackfillMode = "dry-run" | "apply";

type LegacyContactRow = {
  account_id: string;
  email: string | null;
  phone_number: string | null;
};

type CurrentContactRow = {
  account_id: string;
  kind: ContactPointKind;
  normalized_value_hash: string;
};

export type ContactPointBackfillSummary = {
  mode: BackfillMode;
  scannedAccounts: number;
  plannedContacts: number;
  alreadyCurrentContacts: number;
  insertedOrRefreshed: number;
  hasMore: boolean;
  nextAfterAccountId: string | null;
};

function requireSecret(name: string, value: string): string {
  if (new TextEncoder().encode(value).byteLength < 32) {
    throw new Error(`${name} must contain at least 32 UTF-8 bytes.`);
  }
  return value;
}

function requireKeyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 32767) {
    throw new Error("Contact encryption key version must be an integer from 1 to 32767.");
  }
  return value;
}

function requireMode(value: string): BackfillMode {
  if (value === "dry-run" || value === "apply") return value;
  throw new Error("ContactPoint backfill mode must be dry-run or apply.");
}

function requireMaxAccounts(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 1000) {
    throw new Error("ContactPoint backfill maxAccounts must be an integer from 1 to 1000.");
  }
  return value;
}

function optionalCursor(value: string | null | undefined): string | null {
  const cursor = value?.trim() ?? "";
  if (!cursor) return null;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(cursor)) {
    throw new Error("ContactPoint backfill cursor must be a UUID.");
  }
  return cursor.toLowerCase();
}

function currentKey(kind: ContactPointKind, hash: string): string {
  return `${kind}\u0000${hash}`;
}

export async function backfillContactPoints(options: {
  databaseUrl: string;
  hashingSecret: string;
  encryptionKey: string;
  keyVersion: number;
  mode: BackfillMode;
  maxAccounts: number;
  afterAccountId?: string | null;
}): Promise<ContactPointBackfillSummary> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const hashingSecret = requireSecret("Contact hashing secret", options.hashingSecret);
  const encryptionKey: ContactEncryptionKey = {
    secret: requireSecret("Contact encryption key", options.encryptionKey),
    keyVersion: requireKeyVersion(options.keyVersion),
  };
  const mode = requireMode(options.mode);
  const maxAccounts = requireMaxAccounts(options.maxAccounts);
  const afterAccountId = optionalCursor(options.afterAccountId);

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });

  try {
    const tableRows = await sql<{ exists: boolean }[]>`
      select to_regclass('identity.contact_points') is not null as exists
    `;
    if (!tableRows[0]?.exists) {
      throw new Error("identity.contact_points is missing; apply reviewed migrations first.");
    }

    const rows = await sql<LegacyContactRow[]>`
      select a.id::text as account_id,p.email,p.phone_number
      from identity.accounts a
      join lifemate.app_users u
        on u.id=a.legacy_app_user_id and u.status='Active'
      join lifemate.user_profiles p on p.user_id=u.id
      where a.status='Active'
        and (${afterAccountId}::uuid is null or a.id > ${afterAccountId}::uuid)
      order by a.id
      limit ${maxAccounts + 1}
    `;
    const hasMore = rows.length > maxAccounts;
    const batch = rows.slice(0, maxAccounts);

    const current = batch.length === 0
      ? []
      : await sql<CurrentContactRow[]>`
          select account_id::text as account_id,kind,normalized_value_hash
          from identity.contact_points
          where status <> 'Revoked'
            and account_id in ${sql(batch.map((row) => row.account_id))}
          order by account_id,kind
        `;
    const currentByAccount = new Map<string, Map<string, CurrentContactRow>>();
    const globalOwners = await sql<CurrentContactRow[]>`
      select account_id::text as account_id,kind,normalized_value_hash
      from identity.contact_points
      where status <> 'Revoked'
      order by kind,normalized_value_hash
    `;
    const ownerByContact = new Map<string, string>();
    for (const row of globalOwners) {
      const key = currentKey(row.kind, row.normalized_value_hash);
      const owner = ownerByContact.get(key);
      if (owner && owner !== row.account_id) {
        throw new Error("ContactPoint backfill found one current contact owned by multiple Accounts.");
      }
      ownerByContact.set(key, row.account_id);
    }
    for (const row of current) {
      const byKind = currentByAccount.get(row.account_id) ?? new Map<string, CurrentContactRow>();
      if (byKind.has(row.kind)) {
        throw new Error("ContactPoint backfill found duplicate current contacts for one Account/kind.");
      }
      byKind.set(row.kind, row);
      currentByAccount.set(row.account_id, byKind);
    }

    let plannedContacts = 0;
    let alreadyCurrentContacts = 0;
    const patches = new Map<string, { email?: string | null; phone?: string | null }>();
    for (const row of batch) {
      const patch: { email?: string | null; phone?: string | null } = {};
      for (const kind of ["Email", "Phone"] as const) {
        const raw = kind === "Email" ? row.email : row.phone_number;
        if (raw == null || raw.trim().length === 0) continue;
        let normalized: string;
        try {
          normalized = normalizeContactPoint(kind, raw);
        } catch {
          throw new Error("ContactPoint backfill encountered invalid legacy contact data.");
        }
        const expectedHash = await hashContactPoint(hashingSecret, kind, normalized);
        const owner = ownerByContact.get(currentKey(kind, expectedHash));
        if (owner && owner !== row.account_id) {
          throw new Error("ContactPoint backfill conflicts with a contact owned by another Account.");
        }
        const existing = currentByAccount.get(row.account_id)?.get(kind);
        if (existing?.normalized_value_hash === expectedHash) {
          alreadyCurrentContacts += 1;
        }
        plannedContacts += 1;
        if (kind === "Email") patch.email = normalized;
        else patch.phone = normalized;
      }
      if (Object.keys(patch).length > 0) patches.set(row.account_id, patch);
    }

    const nextAfterAccountId = batch.length > 0
      ? batch[batch.length - 1].account_id
      : null;
    if (mode === "dry-run") {
      return {
        mode,
        scannedAccounts: batch.length,
        plannedContacts,
        alreadyCurrentContacts,
        insertedOrRefreshed: 0,
        hasMore,
        nextAfterAccountId,
      };
    }

    const writer = createContactPointWriter(hashingSecret, {
      enabled: true,
      encryptionKey,
    });
    let insertedOrRefreshed = 0;
    await sql.begin(async (transaction) => {
      for (const row of batch) {
        const patch = patches.get(row.account_id);
        if (!patch) continue;
        await writer.syncForAccount(transaction, row.account_id, patch, "replace");
        insertedOrRefreshed += Object.keys(patch).length;
      }
    });

    return {
      mode,
      scannedAccounts: batch.length,
      plannedContacts,
      alreadyCurrentContacts,
      insertedOrRefreshed,
      hasMore,
      nextAfterAccountId,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const mode = requireMode(
    (Deno.env.get("LIFEMATE_CONTACT_BACKFILL_MODE") ?? "dry-run")
      .trim()
      .toLowerCase(),
  );
  if (mode === "apply") {
    const confirmation = Deno.env.get("LIFEMATE_CONTACT_BACKFILL_CONFIRM") ?? "";
    if (confirmation !== "BACKFILL-ENCRYPTED-CONTACTS") {
      throw new Error(
        "Apply mode requires LIFEMATE_CONTACT_BACKFILL_CONFIRM=BACKFILL-ENCRYPTED-CONTACTS.",
      );
    }
  }

  const summary = await backfillContactPoints({
    databaseUrl: Deno.env.get("LIFEMATE_CONTACT_MIGRATION_DATABASE_URL") ?? "",
    hashingSecret: Deno.env.get("LIFEMATE_CONTACT_HASHING_SECRET") ?? "",
    encryptionKey: Deno.env.get("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY") ?? "",
    keyVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION") ?? "",
    ),
    mode,
    maxAccounts: Number(Deno.env.get("LIFEMATE_CONTACT_BACKFILL_MAX_ACCOUNTS") ?? "100"),
    afterAccountId: Deno.env.get("LIFEMATE_CONTACT_BACKFILL_AFTER_ACCOUNT_ID"),
  });
  // Counts plus an opaque pagination cursor only. Never print contact plaintext, hashes, ciphertext, DB URLs or key material.
  console.log(JSON.stringify(summary));
}
