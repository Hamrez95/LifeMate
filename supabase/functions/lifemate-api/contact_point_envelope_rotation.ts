import {
  type ContactEncryptionKey,
  decryptContactPoint,
  encryptContactPoint,
  hashContactPoint,
  type ContactPointKind,
} from "../_shared/contact_point_crypto.ts";
import { ApiError } from "./validation.ts";

export type RotatableContactPointEnvelope = {
  id: string;
  accountId: string;
  kind: ContactPointKind;
  normalizedValueHash: string;
  ciphertextB64: string;
  nonceB64: string;
  keyVersion: number;
};

export type ContactPointEnvelopeValidationResult =
  | { status: "already-active" }
  | { status: "previous-valid"; plaintext: string };

export type ContactPointEnvelopeRotationResult =
  | { status: "already-active" }
  | { status: "rotated" };

export function createContactPointEnvelopeRotator(options: {
  hashingSecret: string;
  activeEncryptionKey: ContactEncryptionKey;
  previousEncryptionKey: ContactEncryptionKey;
}) {
  const hashingSecret = options.hashingSecret;
  const activeKey = options.activeEncryptionKey;
  const previousKey = options.previousEncryptionKey;
  if (new TextEncoder().encode(hashingSecret).byteLength < 32) {
    throw new Error(
      "ContactPoint envelope rotation requires the external contact hashing secret.",
    );
  }
  if (activeKey.keyVersion === previousKey.keyVersion) {
    throw new Error(
      "ContactPoint envelope rotation requires distinct active and previous key versions.",
    );
  }

  async function validate(
    row: RotatableContactPointEnvelope,
  ): Promise<ContactPointEnvelopeValidationResult> {
    if (row.keyVersion === activeKey.keyVersion) {
      return { status: "already-active" };
    }
    if (row.keyVersion !== previousKey.keyVersion) {
      throw unavailable();
    }

    let plaintext: string;
    try {
      plaintext = await decryptContactPoint(
        previousKey,
        {
          accountId: row.accountId,
          kind: row.kind,
          normalizedValueHash: row.normalizedValueHash,
        },
        {
          ciphertextB64: row.ciphertextB64,
          nonceB64: row.nonceB64,
          keyVersion: row.keyVersion,
        },
      );
    } catch {
      throw unavailable();
    }

    let expectedHash: string;
    try {
      expectedHash = await hashContactPoint(
        hashingSecret,
        row.kind,
        plaintext,
      );
    } catch {
      throw unavailable();
    }
    if (expectedHash !== row.normalizedValueHash) {
      throw unavailable();
    }
    return { status: "previous-valid", plaintext };
  }

  async function rotate(
    transaction: any,
    row: RotatableContactPointEnvelope,
  ): Promise<ContactPointEnvelopeRotationResult> {
    const validated = await validate(row);
    if (validated.status === "already-active") {
      return validated;
    }

    const next = await encryptContactPoint(
      activeKey,
      {
        accountId: row.accountId,
        kind: row.kind,
        normalizedValueHash: row.normalizedValueHash,
      },
      validated.plaintext,
    );

    // Only envelope metadata changes. Status and verified_at_utc are deliberately
    // omitted so verification state survives key rotation. The complete old
    // envelope is part of the predicate, making a concurrent writer/rotator a
    // fail-closed optimistic-concurrency conflict instead of a lost update.
    const updated = await transaction`
      update identity.contact_points
      set encrypted_value=decode(${next.ciphertextB64},'base64'),
          encryption_nonce_b64=${next.nonceB64},
          encryption_key_version=${next.keyVersion},
          updated_at_utc=now()
      where id=${row.id}::uuid
        and account_id=${row.accountId}::uuid
        and kind=${row.kind}
        and normalized_value_hash=${row.normalizedValueHash}
        and status <> 'Revoked'
        and encryption_key_version=${row.keyVersion}
        and encryption_nonce_b64=${row.nonceB64}
        and encode(encrypted_value,'base64')=${row.ciphertextB64}
      returning id::text as id
    `;
    if (updated.length !== 1 || updated[0]?.id !== row.id) {
      throw new ApiError(
        409,
        "contact_point_rotation_conflict",
        "Canonical contact data changed during envelope-key rotation.",
      );
    }
    return { status: "rotated" };
  }

  return { validate, rotate };
}

function unavailable(): ApiError {
  return new ApiError(
    503,
    "contact_point_unavailable",
    "Canonical contact data is unavailable.",
  );
}
