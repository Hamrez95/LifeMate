import {
  contactPointDualWriteEnabled,
  encryptContactPoint,
  hashContactPoint,
  type ContactEncryptionKey,
  type ContactPointKind,
  normalizeContactPoint,
  readContactEncryptionKey,
} from "../_shared/contact_point_crypto.ts";
import { ApiError } from "./validation.ts";

type EnvironmentReader = (name: string) => string | null | undefined;

type ContactPointWriterOptions = {
  enabled?: boolean;
  encryptionKey?: ContactEncryptionKey;
  readEnvironment?: EnvironmentReader;
};

export type ContactPointPatch = {
  email?: string | null;
  phone?: string | null;
};

export type ContactPointWriteMode = "replace" | "if-missing";

export function createContactPointWriter(
  hashingSecret: string | undefined,
  options: ContactPointWriterOptions = {},
) {
  const readEnvironment = options.readEnvironment ??
    ((name: string) => Deno.env.get(name));
  const enabled = options.enabled ?? contactPointDualWriteEnabled(readEnvironment);
  const effectiveHashingSecret = hashingSecret ??
    readEnvironment("LIFEMATE_CONTACT_HASHING_SECRET") ?? "";
  let encryptionKey: ContactEncryptionKey | null = null;

  if (enabled) {
    if (
      new TextEncoder().encode(effectiveHashingSecret).byteLength < 32
    ) {
      throw new Error(
        "Encrypted ContactPoint dual-write requires the dedicated LifeMate contact hashing secret.",
      );
    }
    encryptionKey = options.encryptionKey ??
      readContactEncryptionKey(readEnvironment);
  }

  async function resolveAccountId(
    transaction: any,
    legacyAppUserId: string,
  ): Promise<string> {
    const rows = await transaction`
      select identity.account_id_for_legacy_app_user(
        ${legacyAppUserId}::uuid
      )::text as account_id
    `;
    const accountId = rows[0]?.account_id;
    if (typeof accountId !== "string" || accountId.length === 0) {
      throw new ApiError(
        409,
        "identity_account_mapping_missing",
        "The LifeMate account mapping is unavailable.",
      );
    }
    return accountId;
  }

  async function syncForLegacyAppUser(
    transaction: any,
    legacyAppUserId: string,
    patch: ContactPointPatch,
    mode: ContactPointWriteMode = "replace",
  ): Promise<void> {
    if (!enabled) return;
    const accountId = await resolveAccountId(transaction, legacyAppUserId);
    await syncForAccount(transaction, accountId, patch, mode);
  }

  async function syncForAccount(
    transaction: any,
    accountId: string,
    patch: ContactPointPatch,
    mode: ContactPointWriteMode = "replace",
  ): Promise<void> {
    if (!enabled) return;
    if (!encryptionKey || effectiveHashingSecret.length === 0) {
      throw new Error("ContactPoint dual-write configuration is unavailable.");
    }

    if (Object.hasOwn(patch, "email")) {
      await writeKind(
        transaction,
        accountId,
        "Email",
        patch.email ?? null,
        mode,
      );
    }
    if (Object.hasOwn(patch, "phone")) {
      await writeKind(
        transaction,
        accountId,
        "Phone",
        patch.phone ?? null,
        mode,
      );
    }
  }

  async function writeKind(
    transaction: any,
    accountId: string,
    kind: ContactPointKind,
    rawValue: string | null,
    mode: ContactPointWriteMode,
  ): Promise<void> {
    const currentRows = await transaction`
      select id::text as id,account_id::text as account_id,
             normalized_value_hash,status
      from identity.contact_points
      where account_id=${accountId}::uuid
        and kind=${kind}
        and status <> 'Revoked'
      order by updated_at_utc desc,id
      for update
    `;

    if (rawValue == null) {
      if (mode === "if-missing") return;
      await transaction`
        update identity.contact_points
        set status='Revoked',
            encrypted_value=null,
            encryption_nonce_b64=null,
            encryption_key_version=null,
            verified_at_utc=null,
            updated_at_utc=now()
        where account_id=${accountId}::uuid
          and kind=${kind}
          and status <> 'Revoked'
      `;
      return;
    }

    const normalized = normalizeContactPoint(kind, rawValue);
    const normalizedHash = await hashContactPoint(
      effectiveHashingSecret,
      kind,
      normalized,
    );

    if (
      mode === "if-missing" &&
      currentRows.some((row: Record<string, unknown>) =>
        row.normalized_value_hash !== normalizedHash
      )
    ) {
      return;
    }

    const conflicting = await transaction`
      select account_id::text as account_id
      from identity.contact_points
      where kind=${kind}
        and normalized_value_hash=${normalizedHash}
        and status <> 'Revoked'
      for update
    `;
    if (
      conflicting.some((row: Record<string, unknown>) =>
        row.account_id !== accountId
      )
    ) {
      throw new ApiError(
        409,
        "contact_point_conflict",
        "This contact is already linked to another LifeMate account.",
      );
    }

    const envelope = await encryptContactPoint(
      encryptionKey,
      { accountId, kind, normalizedValueHash: normalizedHash },
      normalized,
    );

    // Revoke any prior current value only after encryption + global conflict
    // checks have succeeded, so failures never strand the Account without its
    // previous canonical contact inside the surrounding transaction.
    await transaction`
      update identity.contact_points
      set status='Revoked',
          encrypted_value=null,
          encryption_nonce_b64=null,
          encryption_key_version=null,
          verified_at_utc=null,
          updated_at_utc=now()
      where account_id=${accountId}::uuid
        and kind=${kind}
        and normalized_value_hash <> ${normalizedHash}
        and status <> 'Revoked'
    `;

    const rows = await transaction`
      insert into identity.contact_points(
        account_id,kind,normalized_value_hash,encrypted_value,
        encryption_nonce_b64,encryption_key_version,status,
        created_at_utc,updated_at_utc
      ) values(
        ${accountId}::uuid,${kind},${normalizedHash},
        decode(${envelope.ciphertextB64},'base64'),
        ${envelope.nonceB64},${envelope.keyVersion},'Pending',now(),now()
      )
      on conflict(kind,normalized_value_hash)
        where status <> 'Revoked'
      do update set
        encrypted_value=excluded.encrypted_value,
        encryption_nonce_b64=excluded.encryption_nonce_b64,
        encryption_key_version=excluded.encryption_key_version,
        status=case
          when identity.contact_points.status='Verified' then 'Verified'
          else 'Pending'
        end,
        verified_at_utc=case
          when identity.contact_points.status='Verified'
            then identity.contact_points.verified_at_utc
          else null
        end,
        updated_at_utc=excluded.updated_at_utc
      where identity.contact_points.account_id=excluded.account_id
      returning account_id::text as account_id
    `;
    if (rows[0]?.account_id !== accountId) {
      throw new ApiError(
        409,
        "contact_point_conflict",
        "This contact is already linked to another LifeMate account.",
      );
    }
  }

  return {
    enabled,
    syncForAccount,
    syncForLegacyAppUser,
  };
}
