import postgres from "npm:postgres@3.4.7";
import type { ContactPointKind } from "../../supabase/functions/_shared/contact_point_crypto.ts";
import { createContactPointEnvelopeRotator } from "../../supabase/functions/lifemate-api/contact_point_envelope_rotation.ts";

type RotationMode = "dry-run" | "apply";

type RotationRow = {
  id: string;
  account_id: string;
  kind: ContactPointKind;
  normalized_value_hash: string;
  ciphertext_b64: string;
  encryption_nonce_b64: string;
  encryption_key_version: number;
};

export type ContactPointKeyRotationSummary = {
  mode: RotationMode;
  scannedContacts: number;
  activeVersionContacts: number;
  previousVersionContacts: number;
  rotatedContacts: number;
  hasMore: boolean;
  nextAfterContactPointId: string | null;
};

function requireSecret(name: string, value: string): string {
  if (new TextEncoder().encode(value).byteLength < 32) {
    throw new Error(`${name} must contain at least 32 UTF-8 bytes.`);
  }
  return value;
}

function requireKeyVersion(name: string, value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 32767) {
    throw new Error(`${name} must be an integer from 1 to 32767.`);
  }
  return value;
}

function requireMode(value: string): RotationMode {
  if (value === "dry-run" || value === "apply") return value;
  throw new Error("ContactPoint key rotation mode must be dry-run or apply.");
}

function requireMaxContacts(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 1000) {
    throw new Error(
      "ContactPoint key rotation maxContacts must be an integer from 1 to 1000.",
    );
  }
  return value;
}

function optionalCursor(value: string | null | undefined): string | null {
  const cursor = value?.trim() ?? "";
  if (!cursor) return null;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(cursor)
  ) {
    throw new Error("ContactPoint key rotation cursor must be a UUID.");
  }
  return cursor.toLowerCase();
}

function assertRotationRow(row: RotationRow): RotationRow {
  if (
    typeof row.id !== "string" ||
    typeof row.account_id !== "string" ||
    (row.kind !== "Email" && row.kind !== "Phone") ||
    typeof row.normalized_value_hash !== "string" ||
    !/^[0-9a-f]{64}$/.test(row.normalized_value_hash) ||
    typeof row.ciphertext_b64 !== "string" ||
    row.ciphertext_b64.length === 0 ||
    typeof row.encryption_nonce_b64 !== "string" ||
    row.encryption_nonce_b64.length === 0 ||
    !Number.isSafeInteger(Number(row.encryption_key_version))
  ) {
    throw new Error(
      "ContactPoint key rotation encountered malformed canonical envelope metadata.",
    );
  }
  return row;
}

export async function rotateContactPointEncryptionKeys(options: {
  databaseUrl: string;
  hashingSecret: string;
  activeEncryptionKey: string;
  activeKeyVersion: number;
  previousEncryptionKey: string;
  previousKeyVersion: number;
  mode: RotationMode;
  maxContacts: number;
  afterContactPointId?: string | null;
  confirmation?: string | null;
}): Promise<ContactPointKeyRotationSummary> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const hashingSecret = requireSecret(
    "Contact hashing secret",
    options.hashingSecret,
  );
  const activeEncryptionKey = requireSecret(
    "Active ContactPoint encryption key",
    options.activeEncryptionKey,
  );
  const previousEncryptionKey = requireSecret(
    "Previous ContactPoint encryption key",
    options.previousEncryptionKey,
  );
  const activeKeyVersion = requireKeyVersion(
    "Active ContactPoint encryption key version",
    options.activeKeyVersion,
  );
  const previousKeyVersion = requireKeyVersion(
    "Previous ContactPoint encryption key version",
    options.previousKeyVersion,
  );
  if (activeKeyVersion === previousKeyVersion) {
    throw new Error(
      "Active and previous ContactPoint encryption key versions must differ.",
    );
  }
  const mode = requireMode(options.mode);
  const maxContacts = requireMaxContacts(options.maxContacts);
  const afterContactPointId = optionalCursor(options.afterContactPointId);
  if (
    mode === "apply" &&
    options.confirmation !== "ROTATE-CONTACT-ENVELOPES"
  ) {
    throw new Error(
      "Apply mode requires confirmation ROTATE-CONTACT-ENVELOPES.",
    );
  }

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });
  const rotator = createContactPointEnvelopeRotator({
    hashingSecret,
    activeEncryptionKey: {
      secret: activeEncryptionKey,
      keyVersion: activeKeyVersion,
    },
    previousEncryptionKey: {
      secret: previousEncryptionKey,
      keyVersion: previousKeyVersion,
    },
  });

  try {
    const rows = await sql<RotationRow[]>`
      select id::text as id,account_id::text as account_id,kind,
             normalized_value_hash,
             encode(encrypted_value,'base64') as ciphertext_b64,
             encryption_nonce_b64,encryption_key_version
      from identity.contact_points
      where status <> 'Revoked'
        and (${afterContactPointId}::uuid is null or id > ${afterContactPointId}::uuid)
      order by id
      limit ${maxContacts + 1}
    `;
    const hasMore = rows.length > maxContacts;
    const batch = rows.slice(0, maxContacts).map(assertRotationRow);

    let activeVersionContacts = 0;
    let previousVersionContacts = 0;
    for (const row of batch) {
      const validated = await rotator.validate({
        id: row.id,
        accountId: row.account_id,
        kind: row.kind,
        normalizedValueHash: row.normalized_value_hash,
        ciphertextB64: row.ciphertext_b64,
        nonceB64: row.encryption_nonce_b64,
        keyVersion: Number(row.encryption_key_version),
      });
      if (validated.status === "already-active") activeVersionContacts += 1;
      else previousVersionContacts += 1;
    }

    const nextAfterContactPointId = batch.length > 0
      ? batch[batch.length - 1].id
      : null;
    if (mode === "dry-run") {
      return {
        mode,
        scannedContacts: batch.length,
        activeVersionContacts,
        previousVersionContacts,
        rotatedContacts: 0,
        hasMore,
        nextAfterContactPointId,
      };
    }

    let rotatedContacts = 0;
    await sql.begin(async (transaction) => {
      for (const row of batch) {
        if (Number(row.encryption_key_version) === activeKeyVersion) continue;
        const result = await rotator.rotate(transaction, {
          id: row.id,
          accountId: row.account_id,
          kind: row.kind,
          normalizedValueHash: row.normalized_value_hash,
          ciphertextB64: row.ciphertext_b64,
          nonceB64: row.encryption_nonce_b64,
          keyVersion: Number(row.encryption_key_version),
        });
        if (result.status === "rotated") rotatedContacts += 1;
      }
    });

    return {
      mode,
      scannedContacts: batch.length,
      activeVersionContacts,
      previousVersionContacts,
      rotatedContacts,
      hasMore,
      nextAfterContactPointId,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const mode = requireMode(
    (Deno.env.get("LIFEMATE_CONTACT_KEY_ROTATION_MODE") ?? "dry-run")
      .trim()
      .toLowerCase(),
  );
  const summary = await rotateContactPointEncryptionKeys({
    databaseUrl: Deno.env.get("LIFEMATE_CONTACT_MIGRATION_DATABASE_URL") ?? "",
    hashingSecret: Deno.env.get("LIFEMATE_CONTACT_HASHING_SECRET") ?? "",
    activeEncryptionKey:
      Deno.env.get("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY") ?? "",
    activeKeyVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION") ?? "",
    ),
    previousEncryptionKey:
      Deno.env.get("LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY") ?? "",
    previousKeyVersion: Number(
      Deno.env.get(
        "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
      ) ?? "",
    ),
    mode,
    maxContacts: Number(
      Deno.env.get("LIFEMATE_CONTACT_KEY_ROTATION_MAX_CONTACTS") ?? "100",
    ),
    afterContactPointId: Deno.env.get(
      "LIFEMATE_CONTACT_KEY_ROTATION_AFTER_CONTACT_POINT_ID",
    ),
    confirmation: Deno.env.get("LIFEMATE_CONTACT_KEY_ROTATION_CONFIRM"),
  });
  // Counts plus an opaque pagination cursor only. Plaintext, hashes, ciphertext,
  // nonces, database URLs and key material are intentionally omitted.
  console.log(JSON.stringify(summary));
}
