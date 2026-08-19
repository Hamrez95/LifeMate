import postgres from "npm:postgres@3.4.7";
import {
  decryptProviderIdentitySubject,
  encryptProviderIdentitySubject,
  type ProviderIdentityHandleEnvelope,
  type ProviderIdentityHandleKey,
} from "../../supabase/functions/_shared/provider_identity_handle_crypto.ts";

type RotationMode = "dry-run" | "apply";

type HandleRow = {
  account_id: string;
  ciphertext_b64: string;
  nonce_b64: string;
  key_version: number | string;
};

export type ProviderHandleKeyRotationSummary = {
  mode: RotationMode;
  scannedHandles: number;
  activeVersionHandles: number;
  previousVersionHandles: number;
  rotatedHandles: number;
  hasMore: boolean;
  nextAfterAccountId: string | null;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
  throw new Error("Provider-handle key rotation mode must be dry-run or apply.");
}

function requireMaxHandles(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 1000) {
    throw new Error(
      "Provider-handle key rotation maxHandles must be an integer from 1 to 1000.",
    );
  }
  return value;
}

function optionalCursor(value: string | null | undefined): string | null {
  const cursor = value?.trim() ?? "";
  if (!cursor) return null;
  if (!uuidPattern.test(cursor)) {
    throw new Error("Provider-handle key rotation cursor must be an Account UUID.");
  }
  return cursor.toLowerCase();
}

function assertRow(row: HandleRow): HandleRow {
  if (
    typeof row.account_id !== "string" ||
    !uuidPattern.test(row.account_id) ||
    typeof row.ciphertext_b64 !== "string" ||
    row.ciphertext_b64.length === 0 ||
    typeof row.nonce_b64 !== "string" ||
    row.nonce_b64.length === 0 ||
    !Number.isSafeInteger(Number(row.key_version))
  ) {
    throw new Error(
      "Provider-handle key rotation encountered malformed canonical envelope metadata.",
    );
  }
  return row;
}

async function validatePreviousHandle(
  row: HandleRow,
  activeKey: ProviderIdentityHandleKey,
  previousKey: ProviderIdentityHandleKey,
): Promise<{ status: "active" } | { status: "previous"; subject: string }> {
  const rowVersion = Number(row.key_version);
  if (rowVersion === activeKey.keyVersion) return { status: "active" };
  if (rowVersion !== previousKey.keyVersion) {
    throw new Error("provider_handle_unavailable");
  }
  const envelope: ProviderIdentityHandleEnvelope = {
    ciphertextB64: row.ciphertext_b64,
    nonceB64: row.nonce_b64,
    keyVersion: rowVersion,
  };
  let subject: string;
  try {
    subject = await decryptProviderIdentitySubject(
      previousKey,
      {
        accountId: row.account_id,
        provider: "supabase_auth",
        issuer: "supabase",
      },
      envelope,
    );
  } catch {
    throw new Error("provider_handle_unavailable");
  }
  if (!uuidPattern.test(subject)) {
    throw new Error("provider_handle_unavailable");
  }
  return { status: "previous", subject };
}

export async function rotateProviderIdentityHandleKeys(options: {
  databaseUrl: string;
  activeEncryptionKey: string;
  activeKeyVersion: number;
  previousEncryptionKey: string;
  previousKeyVersion: number;
  mode: RotationMode;
  maxHandles: number;
  afterAccountId?: string | null;
  confirmation?: string | null;
}): Promise<ProviderHandleKeyRotationSummary> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const activeKey: ProviderIdentityHandleKey = {
    secret: requireSecret(
      "Active provider identity-handle key",
      options.activeEncryptionKey,
    ),
    keyVersion: requireKeyVersion(
      "Active provider identity-handle key version",
      options.activeKeyVersion,
    ),
  };
  const previousKey: ProviderIdentityHandleKey = {
    secret: requireSecret(
      "Previous provider identity-handle key",
      options.previousEncryptionKey,
    ),
    keyVersion: requireKeyVersion(
      "Previous provider identity-handle key version",
      options.previousKeyVersion,
    ),
  };
  if (activeKey.keyVersion === previousKey.keyVersion) {
    throw new Error(
      "Active and previous provider identity-handle key versions must differ.",
    );
  }
  const mode = requireMode(options.mode);
  const maxHandles = requireMaxHandles(options.maxHandles);
  const afterAccountId = optionalCursor(options.afterAccountId);
  if (mode === "apply" && options.confirmation !== "ROTATE-PROVIDER-HANDLES") {
    throw new Error(
      "Apply mode requires confirmation ROTATE-PROVIDER-HANDLES.",
    );
  }

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });
  try {
    const rows = await sql<HandleRow[]>`
      select account_id::text as account_id,ciphertext_b64,nonce_b64,key_version
      from identity.provider_identity_handles
      where provider='supabase_auth'
        and issuer='supabase'
        and status='Active'
        and (${afterAccountId}::uuid is null or account_id > ${afterAccountId}::uuid)
      order by account_id
      limit ${maxHandles + 1}
    `;
    const hasMore = rows.length > maxHandles;
    const batch = rows.slice(0, maxHandles).map(assertRow);
    const validated: Array<{
      row: HandleRow;
      result: { status: "active" } | { status: "previous"; subject: string };
    }> = [];
    let activeVersionHandles = 0;
    let previousVersionHandles = 0;
    for (const row of batch) {
      const result = await validatePreviousHandle(row, activeKey, previousKey);
      validated.push({ row, result });
      if (result.status === "active") activeVersionHandles += 1;
      else previousVersionHandles += 1;
    }
    const nextAfterAccountId = batch.length > 0
      ? batch[batch.length - 1].account_id
      : null;
    if (mode === "dry-run") {
      return {
        mode,
        scannedHandles: batch.length,
        activeVersionHandles,
        previousVersionHandles,
        rotatedHandles: 0,
        hasMore,
        nextAfterAccountId,
      };
    }

    let rotatedHandles = 0;
    await sql.begin(async (transaction) => {
      for (const entry of validated) {
        if (entry.result.status === "active") continue;
        const next = await encryptProviderIdentitySubject(
          activeKey,
          {
            accountId: entry.row.account_id,
            provider: "supabase_auth",
            issuer: "supabase",
          },
          entry.result.subject,
        );
        const updated = await transaction`
          update identity.provider_identity_handles
          set ciphertext_b64=${next.ciphertextB64},
              nonce_b64=${next.nonceB64},
              key_version=${next.keyVersion},
              updated_at_utc=now()
          where account_id=${entry.row.account_id}::uuid
            and provider='supabase_auth'
            and issuer='supabase'
            and status='Active'
            and ciphertext_b64=${entry.row.ciphertext_b64}
            and nonce_b64=${entry.row.nonce_b64}
            and key_version=${Number(entry.row.key_version)}
          returning account_id::text as account_id
        `;
        if (
          updated.length !== 1 ||
          updated[0]?.account_id !== entry.row.account_id
        ) {
          throw new Error("provider_handle_rotation_conflict");
        }
        rotatedHandles += 1;
      }
    });

    return {
      mode,
      scannedHandles: batch.length,
      activeVersionHandles,
      previousVersionHandles,
      rotatedHandles,
      hasMore,
      nextAfterAccountId,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const mode = requireMode(
    (Deno.env.get("LIFEMATE_PROVIDER_HANDLE_KEY_ROTATION_MODE") ?? "dry-run")
      .trim()
      .toLowerCase(),
  );
  const summary = await rotateProviderIdentityHandleKeys({
    databaseUrl: Deno.env.get("LIFEMATE_IDENTITY_MIGRATION_DATABASE_URL") ?? "",
    activeEncryptionKey:
      Deno.env.get("LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY") ?? "",
    activeKeyVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION") ?? "",
    ),
    previousEncryptionKey:
      Deno.env.get("LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY") ?? "",
    previousKeyVersion: Number(
      Deno.env.get("LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION") ??
        "",
    ),
    mode,
    maxHandles: Number(
      Deno.env.get("LIFEMATE_PROVIDER_HANDLE_KEY_ROTATION_MAX_HANDLES") ?? "100",
    ),
    afterAccountId: Deno.env.get(
      "LIFEMATE_PROVIDER_HANDLE_KEY_ROTATION_AFTER_ACCOUNT_ID",
    ),
    confirmation: Deno.env.get("LIFEMATE_PROVIDER_HANDLE_KEY_ROTATION_CONFIRM"),
  });
  console.log(JSON.stringify(summary));
}
