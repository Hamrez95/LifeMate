const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const envelopeVersion = 1;
const nonceLength = 12;
const keySalt = encoder.encode("lifemate:provider-identity-handle:v1");

type EnvironmentReader = (name: string) => string | null | undefined;

export type ProviderIdentityHandleKey = {
  secret: string;
  keyVersion: number;
};

export type ProviderIdentityHandleKeySet = {
  active: ProviderIdentityHandleKey;
  previous: ProviderIdentityHandleKey | null;
};

export type ProviderIdentityHandleEnvelope = {
  ciphertextB64: string;
  nonceB64: string;
  keyVersion: number;
};

export type ProviderIdentityHandleContext = {
  accountId: string;
  provider: string;
  issuer: string;
};

function readBoolean(
  name: string,
  readEnvironment: EnvironmentReader,
): boolean {
  const raw = (readEnvironment(name) ?? "").trim().toLowerCase();
  if (!raw || raw === "false") return false;
  if (raw === "true") return true;
  throw new Error(`${name} must be either true or false.`);
}

function requiredKeyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 32767) {
    throw new Error("Provider identity-handle key version is invalid.");
  }
  return value;
}

function normalizedContext(
  context: ProviderIdentityHandleContext,
): ProviderIdentityHandleContext {
  const accountId = context.accountId.trim().toLowerCase();
  const provider = context.provider.trim().toLowerCase();
  const issuer = context.issuer.trim();
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(accountId)
  ) {
    throw new Error("Provider identity-handle accountId is invalid.");
  }
  if (!provider || provider.length > 80) {
    throw new Error("Provider identity-handle provider is invalid.");
  }
  if (!issuer || issuer.length > 255) {
    throw new Error("Provider identity-handle issuer is invalid.");
  }
  return { accountId, provider, issuer };
}

function ownedArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer as ArrayBuffer;
}

function canonicalAad(
  context: ProviderIdentityHandleContext,
  keyVersion: number,
): ArrayBuffer {
  const normalized = normalizedContext(context);
  return ownedArrayBuffer(encoder.encode(JSON.stringify({
    envelopeVersion,
    accountId: normalized.accountId,
    provider: normalized.provider,
    issuer: normalized.issuer,
    keyVersion: requiredKeyVersion(keyVersion),
  })));
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

async function deriveAesKey(
  key: ProviderIdentityHandleKey,
  usage: "encrypt" | "decrypt",
): Promise<CryptoKey> {
  const secretBytes = encoder.encode(key.secret);
  if (secretBytes.byteLength < 32) {
    throw new Error(
      "Provider identity-handle key must contain at least 32 UTF-8 bytes.",
    );
  }
  const version = requiredKeyVersion(key.keyVersion);
  const root = await crypto.subtle.importKey(
    "raw",
    secretBytes,
    "HKDF",
    false,
    ["deriveKey"],
  );
  return await crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: keySalt,
      info: encoder.encode(`provider-subject|key-version:${version}`),
    },
    root,
    { name: "AES-GCM", length: 256 },
    false,
    [usage],
  );
}

export function providerIdentityHandleDualWriteEnabled(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): boolean {
  return readBoolean(
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE",
    readEnvironment,
  );
}

export function rawIdentityRetirementEnabled(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): boolean {
  return readBoolean("LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT", readEnvironment);
}

function readConfiguredProviderIdentityHandleKey(
  readEnvironment: EnvironmentReader,
  secretName: string,
  versionName: string,
): ProviderIdentityHandleKey {
  const secret = readEnvironment(secretName) ?? "";
  const versionRaw = readEnvironment(versionName) ?? "";
  if (encoder.encode(secret).byteLength < 32) {
    throw new Error(
      `${secretName} must be configured as an external runtime secret with at least 32 UTF-8 bytes.`,
    );
  }
  if (!/^\d+$/.test(versionRaw)) {
    throw new Error(`${versionName} must be configured.`);
  }
  return { secret, keyVersion: requiredKeyVersion(Number(versionRaw)) };
}

export function readProviderIdentityHandleKey(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): ProviderIdentityHandleKey {
  return readConfiguredProviderIdentityHandleKey(
    readEnvironment,
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY",
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION",
  );
}

export function readProviderIdentityHandleKeySet(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): ProviderIdentityHandleKeySet {
  const active = readProviderIdentityHandleKey(readEnvironment);
  const previousSecret =
    readEnvironment("LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY") ?? "";
  const previousVersion = readEnvironment(
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION",
  ) ?? "";
  const hasPreviousSecret = previousSecret.length > 0;
  const hasPreviousVersion = previousVersion.trim().length > 0;
  if (hasPreviousSecret !== hasPreviousVersion) {
    throw new Error(
      "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY and LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION must be configured together.",
    );
  }
  if (!hasPreviousSecret) return { active, previous: null };

  const previous = readConfiguredProviderIdentityHandleKey(
    readEnvironment,
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY",
    "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION",
  );
  if (previous.keyVersion === active.keyVersion) {
    throw new Error(
      "Previous provider identity-handle key version must differ from the active key version.",
    );
  }
  return { active, previous };
}

export async function encryptProviderIdentitySubject(
  key: ProviderIdentityHandleKey,
  context: ProviderIdentityHandleContext,
  subject: string,
  nonceOverride?: Uint8Array,
): Promise<ProviderIdentityHandleEnvelope> {
  const normalizedSubject = subject.trim();
  if (!normalizedSubject || normalizedSubject.length > 512) {
    throw new Error("Provider identity subject is invalid.");
  }
  const nonce = nonceOverride ??
    crypto.getRandomValues(new Uint8Array(nonceLength));
  if (nonce.byteLength !== nonceLength) {
    throw new Error("Provider identity-handle nonce must be 12 bytes.");
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
    encoder.encode(normalizedSubject),
  );
  return {
    ciphertextB64: bytesToBase64(new Uint8Array(encrypted)),
    nonceB64: bytesToBase64(nonce),
    keyVersion: key.keyVersion,
  };
}

export async function decryptProviderIdentitySubject(
  key: ProviderIdentityHandleKey,
  context: ProviderIdentityHandleContext,
  envelope: ProviderIdentityHandleEnvelope,
): Promise<string> {
  if (envelope.keyVersion !== key.keyVersion) {
    throw new Error("Provider identity-handle key version does not match.");
  }
  const nonce = base64ToBytes(envelope.nonceB64, "provider handle nonce");
  if (nonce.byteLength !== nonceLength) {
    throw new Error("Provider identity-handle nonce must be 12 bytes.");
  }
  const ciphertext = base64ToBytes(
    envelope.ciphertextB64,
    "provider handle ciphertext",
  );
  if (ciphertext.byteLength < 17 || ciphertext.byteLength > 4096) {
    throw new Error("Provider identity-handle ciphertext is invalid.");
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
    throw new Error("Provider identity-handle authentication failed.");
  }
  const subject = decoder.decode(plaintext).trim();
  if (!subject || subject.length > 512) {
    throw new Error("Provider identity-handle plaintext is invalid.");
  }
  return subject;
}
