import postgres from "npm:postgres@3.4.7";
import {
  decryptContactPoint,
  hashContactPoint,
  normalizeContactPoint,
  type ContactEncryptionKey,
  type ContactPointKind,
} from "../../supabase/functions/_shared/contact_point_crypto.ts";

type ActiveAccountRow = {
  account_id: string;
  email: string | null;
  phone_number: string | null;
};

type CanonicalContactRow = {
  account_id: string;
  kind: ContactPointKind;
  normalized_value_hash: string;
  ciphertext_b64: string | null;
  encryption_nonce_b64: string | null;
  encryption_key_version: number | null;
};

type KindCounters = {
  legacyPresent: number;
  canonicalPresent: number;
  missingCanonical: number;
  mismatchedCanonical: number;
  conflictingOwner: number;
  invalidEnvelope: number;
  invalidLegacy: number;
  unexpectedCanonical: number;
  duplicateCurrent: number;
};

export type ContactPointReadiness = {
  keyVersion: number;
  activeAccounts: number;
  unmappedActiveAccounts: number;
  email: KindCounters;
  phone: KindCounters;
  readyForContactOnly: boolean;
};

function emptyCounters(): KindCounters {
  return {
    legacyPresent: 0,
    canonicalPresent: 0,
    missingCanonical: 0,
    mismatchedCanonical: 0,
    conflictingOwner: 0,
    invalidEnvelope: 0,
    invalidLegacy: 0,
    unexpectedCanonical: 0,
    duplicateCurrent: 0,
  };
}

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

function contactKey(accountId: string, kind: ContactPointKind): string {
  return `${accountId}\u0000${kind}`;
}

function hashKey(kind: ContactPointKind, hash: string): string {
  return `${kind}\u0000${hash}`;
}

function legacyValue(row: ActiveAccountRow, kind: ContactPointKind): string | null {
  return kind === "Email" ? row.email : row.phone_number;
}

function countersFor(
  result: ContactPointReadiness,
  kind: ContactPointKind,
): KindCounters {
  return kind === "Email" ? result.email : result.phone;
}

export async function assessContactPointReadiness(options: {
  databaseUrl: string;
  hashingSecret: string;
  encryptionKey: string;
  keyVersion: number;
}): Promise<ContactPointReadiness> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const hashingSecret = requireSecret("Contact hashing secret", options.hashingSecret);
  const key: ContactEncryptionKey = {
    secret: requireSecret("Contact encryption key", options.encryptionKey),
    keyVersion: requireKeyVersion(options.keyVersion),
  };

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });

  try {
    const mappedAccounts = await sql<ActiveAccountRow[]>`
      select a.id::text as account_id,p.email,p.phone_number
      from identity.accounts a
      join lifemate.app_users u
        on u.id=a.legacy_app_user_id and u.status='Active'
      join lifemate.user_profiles p on p.user_id=u.id
      where a.status='Active'
      order by a.id
    `;
    const unmappedRows = await sql<{ count: number }[]>`
      select count(*)::int as count
      from identity.accounts a
      left join lifemate.app_users u
        on u.id=a.legacy_app_user_id and u.status='Active'
      left join lifemate.user_profiles p on p.user_id=u.id
      where a.status='Active' and (u.id is null or p.id is null)
    `;
    const canonical = await sql<CanonicalContactRow[]>`
      select account_id::text as account_id,kind,normalized_value_hash,
             encode(encrypted_value,'base64') as ciphertext_b64,
             encryption_nonce_b64,encryption_key_version
      from identity.contact_points
      where status <> 'Revoked' and kind in ('Email','Phone')
      order by account_id,kind,id
    `;

    const result: ContactPointReadiness = {
      keyVersion: key.keyVersion,
      activeAccounts: mappedAccounts.length,
      unmappedActiveAccounts: Number(unmappedRows[0]?.count ?? 0),
      email: emptyCounters(),
      phone: emptyCounters(),
      readyForContactOnly: false,
    };

    const rowsByAccountKind = new Map<string, CanonicalContactRow[]>();
    const ownersByKindHash = new Map<string, Set<string>>();
    for (const row of canonical) {
      const bucketKey = contactKey(row.account_id, row.kind);
      const bucket = rowsByAccountKind.get(bucketKey) ?? [];
      bucket.push(row);
      rowsByAccountKind.set(bucketKey, bucket);

      const ownerKey = hashKey(row.kind, row.normalized_value_hash);
      const owners = ownersByKindHash.get(ownerKey) ?? new Set<string>();
      owners.add(row.account_id);
      ownersByKindHash.set(ownerKey, owners);
      countersFor(result, row.kind).canonicalPresent += 1;
    }

    for (const account of mappedAccounts) {
      for (const kind of ["Email", "Phone"] as const) {
        const counters = countersFor(result, kind);
        const ownRows = rowsByAccountKind.get(contactKey(account.account_id, kind)) ?? [];
        if (ownRows.length > 1) counters.duplicateCurrent += ownRows.length - 1;

        const rawLegacy = legacyValue(account, kind);
        if (rawLegacy == null || rawLegacy.trim().length === 0) {
          if (ownRows.length > 0) counters.unexpectedCanonical += ownRows.length;
          continue;
        }
        counters.legacyPresent += 1;

        let normalized: string;
        let expectedHash: string;
        try {
          normalized = normalizeContactPoint(kind, rawLegacy);
          expectedHash = await hashContactPoint(hashingSecret, kind, normalized);
        } catch {
          counters.invalidLegacy += 1;
          continue;
        }

        const expectedOwners = ownersByKindHash.get(hashKey(kind, expectedHash));
        if (expectedOwners && [...expectedOwners].some((owner) => owner !== account.account_id)) {
          counters.conflictingOwner += 1;
        }

        if (ownRows.length === 0) {
          counters.missingCanonical += 1;
          continue;
        }

        const matching = ownRows.find((row) => row.normalized_value_hash === expectedHash);
        if (!matching) {
          counters.mismatchedCanonical += 1;
          continue;
        }

        if (
          !matching.ciphertext_b64 ||
          !matching.encryption_nonce_b64 ||
          matching.encryption_key_version !== key.keyVersion
        ) {
          counters.invalidEnvelope += 1;
          continue;
        }

        try {
          const decrypted = await decryptContactPoint(
            key,
            {
              accountId: account.account_id,
              kind,
              normalizedValueHash: expectedHash,
            },
            {
              ciphertextB64: matching.ciphertext_b64,
              nonceB64: matching.encryption_nonce_b64,
              keyVersion: matching.encryption_key_version,
            },
          );
          if (decrypted !== normalized) counters.invalidEnvelope += 1;
        } catch {
          counters.invalidEnvelope += 1;
        }
      }
    }

    const blocking = [result.email, result.phone].some((counters) =>
      counters.missingCanonical !== 0 ||
      counters.mismatchedCanonical !== 0 ||
      counters.conflictingOwner !== 0 ||
      counters.invalidEnvelope !== 0 ||
      counters.invalidLegacy !== 0 ||
      counters.unexpectedCanonical !== 0 ||
      counters.duplicateCurrent !== 0
    );
    result.readyForContactOnly = !blocking && result.unmappedActiveAccounts === 0;
    return result;
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const result = await assessContactPointReadiness({
    databaseUrl: Deno.env.get("LIFEMATE_CONTACT_MIGRATION_DATABASE_URL") ?? "",
    hashingSecret: Deno.env.get("LIFEMATE_CONTACT_HASHING_SECRET") ?? "",
    encryptionKey: Deno.env.get("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY") ?? "",
    keyVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION") ?? "",
    ),
  });
  // Count-only migration evidence. Plaintext contacts, hashes, ciphertext, DB URLs and key material are never emitted.
  console.log(JSON.stringify(result));
  if (!result.readyForContactOnly) Deno.exit(2);
}
