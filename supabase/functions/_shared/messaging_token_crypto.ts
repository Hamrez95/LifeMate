const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const salt = encoder.encode("lifemate:messaging-token-envelope:v1");
const nonceLength = 12;

type EnvironmentReader = (name: string) => string | null | undefined;

export type MessagingTokenKey = {
  secret: string;
  keyVersion: number;
};

export type MessagingTokenEnvelope = {
  ciphertextB64: string;
  nonceB64: string;
  keyVersion: number;
};

export type MessagingTokenContext = {
  accountId: string;
  productCode: string;
  provider: string;
  tokenHash: string;
};

function owned(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer as ArrayBuffer;
}

function b64(bytes: Uint8Array): string {
  let value = "";
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value);
}

function fromB64(value: string): Uint8Array {
  const raw = atob(value);
  const bytes = new Uint8Array(raw.length);
  for (let index = 0; index < raw.length; index++) bytes[index] = raw.charCodeAt(index);
  return bytes;
}

function uuid(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(normalized)) {
    throw new Error("Messaging token accountId is invalid.");
  }
  return normalized;
}

function keyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 32767) {
    throw new Error("Messaging token key version is invalid.");
  }
  return value;
}

function canonicalContext(context: MessagingTokenContext, version: number): ArrayBuffer {
  const productCode = context.productCode.trim().toLowerCase();
  const provider = context.provider.trim().toLowerCase();
  const tokenHash = context.tokenHash.trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9_.:-]{0,63}$/.test(productCode) ||
      !/^[a-z0-9][a-z0-9_.-]{1,39}$/.test(provider) ||
      !/^[0-9a-f]{64}$/.test(tokenHash)) {
    throw new Error("Messaging token envelope context is invalid.");
  }
  return owned(encoder.encode(JSON.stringify({
    envelopeVersion: 1,
    accountId: uuid(context.accountId),
    productCode,
    provider,
    tokenHash,
    keyVersion: keyVersion(version),
  })));
}

async function aes(key: MessagingTokenKey, usage: "encrypt" | "decrypt"): Promise<CryptoKey> {
  const secret = encoder.encode(key.secret);
  if (secret.byteLength < 32) throw new Error("Messaging token encryption key is too short.");
  const root = await crypto.subtle.importKey("raw", owned(secret), "HKDF", false, ["deriveKey"]);
  return await crypto.subtle.deriveKey({
    name: "HKDF",
    hash: "SHA-256",
    salt: owned(salt),
    info: owned(encoder.encode(`messaging-token|key-version:${keyVersion(key.keyVersion)}`)),
  }, root, { name: "AES-GCM", length: 256 }, false, [usage]);
}

export function readMessagingTokenKey(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): MessagingTokenKey {
  const secret = readEnvironment("LIFEMATE_MESSAGING_TOKEN_ENCRYPTION_KEY") ?? "";
  const rawVersion = readEnvironment("LIFEMATE_MESSAGING_TOKEN_ENCRYPTION_KEY_VERSION") ?? "";
  if (encoder.encode(secret).byteLength < 32 || !/^\d+$/.test(rawVersion)) {
    throw new Error("Messaging token encryption configuration is unavailable.");
  }
  return { secret, keyVersion: keyVersion(Number(rawVersion)) };
}

export async function hashMessagingToken(secret: string, token: string): Promise<string> {
  if (encoder.encode(secret).byteLength < 32) throw new Error("Messaging token hashing secret is too short.");
  const normalized = token.trim();
  if (normalized.length < 20 || normalized.length > 4096) throw new Error("Push token is invalid.");
  const key = await crypto.subtle.importKey("raw", owned(encoder.encode(secret)), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, owned(encoder.encode(`lifemate:messaging-token:v1|${normalized}`)));
  return [...new Uint8Array(signature)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export async function encryptMessagingToken(
  key: MessagingTokenKey,
  context: MessagingTokenContext,
  token: string,
  nonceOverride?: Uint8Array,
): Promise<MessagingTokenEnvelope> {
  const normalized = token.trim();
  if (normalized.length < 20 || normalized.length > 4096) throw new Error("Push token is invalid.");
  const nonce = nonceOverride ?? crypto.getRandomValues(new Uint8Array(nonceLength));
  if (nonce.byteLength !== nonceLength) throw new Error("Messaging token nonce is invalid.");
  const ciphertext = await crypto.subtle.encrypt({
    name: "AES-GCM",
    iv: owned(nonce),
    additionalData: canonicalContext(context, key.keyVersion),
    tagLength: 128,
  }, await aes(key, "encrypt"), owned(encoder.encode(normalized)));
  return { ciphertextB64: b64(new Uint8Array(ciphertext)), nonceB64: b64(nonce), keyVersion: key.keyVersion };
}

export async function decryptMessagingToken(
  key: MessagingTokenKey,
  context: MessagingTokenContext,
  envelope: MessagingTokenEnvelope,
): Promise<string> {
  if (envelope.keyVersion !== key.keyVersion) throw new Error("Messaging token key version does not match.");
  const nonce = fromB64(envelope.nonceB64);
  const ciphertext = fromB64(envelope.ciphertextB64);
  if (nonce.byteLength !== nonceLength || ciphertext.byteLength < 17 || ciphertext.byteLength > 8192) {
    throw new Error("Messaging token envelope is invalid.");
  }
  let plaintext: ArrayBuffer;
  try {
    plaintext = await crypto.subtle.decrypt({
      name: "AES-GCM",
      iv: owned(nonce),
      additionalData: canonicalContext(context, key.keyVersion),
      tagLength: 128,
    }, await aes(key, "decrypt"), owned(ciphertext));
  } catch {
    throw new Error("Messaging token authentication failed.");
  }
  const token = decoder.decode(plaintext).trim();
  if (token.length < 20 || token.length > 4096) throw new Error("Push token is invalid.");
  return token;
}
