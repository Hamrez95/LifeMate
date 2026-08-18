const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const envelopeVersion = 1;
const nonceLength = 12;
const keySalt = encoder.encode("lifemate:contact-point-envelope:v1");

type EnvironmentReader = (name: string) => string | null | undefined;

export type ContactPointKind = "Email" | "Phone";

export type ContactEncryptionKey = {
  secret: string;
  keyVersion: number;
};

export type ContactEncryptionKeySet = {
  active: ContactEncryptionKey;
  previous: ContactEncryptionKey | null;
};

export type ContactPointEnvelope = {
  ciphertextB64: string;
  nonceB64: string;
  keyVersion: number;
};

export type ContactPointContext = {
  accountId: string;
  kind: ContactPointKind;
  normalizedValueHash: string;
};

function ownedArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer as ArrayBuffer;
}

function requiredKeyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 32767) {
    throw new Error("Contact encryption key version is invalid.");
  }
  return value;
}

function normalizedAccountId(value: string): string {
  const accountId = value.trim().toLowerCase();
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
      accountId,
    )
  ) {
    throw new Error("ContactPoint accountId is invalid.");
  }
  return accountId;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const value of bytes) binary += String.fromCharCode(value);
  return btoa(binary);
}

function base64ToBytes(value: string, field: string): Uint8Array {
  try {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    throw new Error(`${field} is not valid base64.`);
  }
}

function readBoolean(
  name: string,
  readEnvironment: EnvironmentReader,
): boolean {
  const raw = (readEnvironment(name) ?? "").trim().toLowerCase();
  if (!raw || raw === "false") return false;
  if (raw === "true") return true;
  throw new Error(`${name} must be either true or false.`);
}

export function contactPointDualWriteEnabled(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): boolean {
  return readBoolean("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", readEnvironment);
}

function readConfiguredContactEncryptionKey(
  readEnvironment: EnvironmentReader,
  secretName: string,
  versionName: string,
): ContactEncryptionKey {
  const secret = readEnvironment(secretName) ?? "";
  const versionRaw = readEnvironment(versionName) ?? "";
  if (encoder.encode(secret).byteLength < 32) {
    throw new Error(
      `${secretName} must be an external secret with at least 32 UTF-8 bytes.`,
    );
  }
  if (!/^\d+$/.test(versionRaw)) {
    throw new Error(`${versionName} must be configured.`);
  }
  return { secret, keyVersion: requiredKeyVersion(Number(versionRaw)) };
}

export function readContactEncryptionKey(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): ContactEncryptionKey {
  return readConfiguredContactEncryptionKey(
    readEnvironment,
    "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
    "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
  );
}

export function readContactEncryptionKeySet(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): ContactEncryptionKeySet {
  const active = readContactEncryptionKey(readEnvironment);
  const previousSecret =
    readEnvironment("LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY") ?? "";
  const previousVersion = readEnvironment(
    "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
  ) ?? "";
  const hasPreviousSecret = previousSecret.length > 0;
  const hasPreviousVersion = previousVersion.trim().length > 0;

  if (hasPreviousSecret !== hasPreviousVersion) {
    throw new Error(
      "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY and LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION must be configured together.",
    );
  }
  if (!hasPreviousSecret) return { active, previous: null };

  const previous = readConfiguredContactEncryptionKey(
    readEnvironment,
    "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY",
    "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
  );
  if (previous.keyVersion === active.keyVersion) {
    throw new Error(
      "Previous ContactPoint encryption key version must differ from the active key version.",
    );
  }
  return { active, previous };
}

export function normalizeContactPoint(
  kind: ContactPointKind,
  value: string,
): string {
  const trimmed = value.trim();
  if (kind === "Email") {
    const normalized = trimmed.toLowerCase();
    if (
      normalized.length < 3 ||
      normalized.length > 320 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)
    ) {
      throw new Error("ContactPoint email is invalid.");
    }
    return normalized;
  }

  const compact = trimmed.replace(/[\s()-]/g, "");
  if (!/^\+?[0-9]{7,15}$/.test(compact)) {
    throw new Error("ContactPoint phone is invalid.");
  }
  return compact;
}

export async function hashContactPoint(
  hashingSecret: string,
  kind: ContactPointKind,
  normalizedValue: string,
): Promise<string> {
  const secretBytes = encoder.encode(hashingSecret);
  if (secretBytes.byteLength < 32) {
    throw new Error("Contact hashing secret must contain at least 32 UTF-8 bytes.");
  }
  const normalized = normalizeContactPoint(kind, normalizedValue);
  const key = await crypto.subtle.importKey(
    "raw",
    ownedArrayBuffer(secretBytes),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    ownedArrayBuffer(
      encoder.encode(`lifemate:contact-point:v1|${kind}|${normalized}`),
    ),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function canonicalAad(
  context: ContactPointContext,
  keyVersion: number,
): ArrayBuffer {
  const hash = context.normalizedValueHash.trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(hash)) {
    throw new Error("ContactPoint normalized hash is invalid.");
  }
  return ownedArrayBuffer(encoder.encode(JSON.stringify({
    envelopeVersion,
    accountId: normalizedAccountId(context.accountId),
    kind: context.kind,
    normalizedValueHash: hash,
    keyVersion: requiredKeyVersion(keyVersion),
  })));
}

async function deriveAesKey(
  key: ContactEncryptionKey,
  usage: "encrypt" | "decrypt",
): Promise<CryptoKey> {
  const secretBytes = encoder.encode(key.secret);
  if (secretBytes.byteLength < 32) {
    throw new Error("Contact encryption key must contain at least 32 UTF-8 bytes.");
  }
  const version = requiredKeyVersion(key.keyVersion);
  const root = await crypto.subtle.importKey(
    "raw",
    ownedArrayBuffer(secretBytes),
    "HKDF",
    false,
    ["deriveKey"],
  );
  return await crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: ownedArrayBuffer(keySalt),
      info: ownedArrayBuffer(
        encoder.encode(`contact-point|key-version:${version}`),
      ),
    },
    root,
    { name: "AES-GCM", length: 256 },
    false,
    [usage],
  );
}

export async function encryptContactPoint(
  key: ContactEncryptionKey,
  context: ContactPointContext,
  normalizedValue: string,
  nonceOverride?: Uint8Array,
): Promise<ContactPointEnvelope> {
  const normalized = normalizeContactPoint(context.kind, normalizedValue);
  const nonce = nonceOverride ?? crypto.getRandomValues(new Uint8Array(nonceLength));
  if (nonce.byteLength !== nonceLength) {
    throw new Error("ContactPoint nonce must be 12 bytes.");
  }
  const aesKey = await deriveAesKey(key, "encrypt");
  const encrypted = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv: ownedArrayBuffer(nonce),
      additionalData: canonicalAad(context, key.keyVersion),
      tagLength: 128,
    },
    aesKey,
    ownedArrayBuffer(encoder.encode(normalized)),
  );
  return {
    ciphertextB64: bytesToBase64(new Uint8Array(encrypted)),
    nonceB64: bytesToBase64(nonce),
    keyVersion: key.keyVersion,
  };
}

export async function decryptContactPoint(
  key: ContactEncryptionKey,
  context: ContactPointContext,
  envelope: ContactPointEnvelope,
): Promise<string> {
  if (envelope.keyVersion !== key.keyVersion) {
    throw new Error("ContactPoint key version does not match.");
  }
  const nonce = base64ToBytes(envelope.nonceB64, "ContactPoint nonce");
  const ciphertext = base64ToBytes(
    envelope.ciphertextB64,
    "ContactPoint ciphertext",
  );
  if (nonce.byteLength !== nonceLength) {
    throw new Error("ContactPoint nonce must be 12 bytes.");
  }
  if (ciphertext.byteLength < 17 || ciphertext.byteLength > 4096) {
    throw new Error("ContactPoint ciphertext is invalid.");
  }
  const aesKey = await deriveAesKey(key, "decrypt");
  let plaintext: ArrayBuffer;
  try {
    plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: ownedArrayBuffer(nonce),
        additionalData: canonicalAad(context, key.keyVersion),
        tagLength: 128,
      },
      aesKey,
      ownedArrayBuffer(ciphertext),
    );
  } catch {
    throw new Error("ContactPoint authentication failed.");
  }
  return normalizeContactPoint(context.kind, decoder.decode(plaintext));
}
