import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  decryptMessagingToken,
  encryptMessagingToken,
  hashMessagingToken,
  readMessagingTokenKey,
  readMessagingTokenKeySet,
} from "./messaging_token_crypto.ts";

Deno.test("messaging token envelope round-trips with bound authenticated context", async () => {
  const key = { secret: "messaging-token-encryption-secret-32-bytes-minimum", keyVersion: 7 };
  const token = "fcm-registration-token-with-high-entropy-123456789";
  const tokenHash = await hashMessagingToken("messaging-token-hashing-secret-32-bytes-minimum", token);
  const context = {
    accountId: "11111111-1111-4111-8111-111111111111",
    productCode: "wellmate",
    provider: "fcm",
    tokenHash,
  };
  const envelope = await encryptMessagingToken(key, context, token, new Uint8Array(12).fill(5));
  assertEquals(envelope.keyVersion, 7);
  assertEquals(await decryptMessagingToken(key, context, envelope), token);
  await assertRejects(() => decryptMessagingToken(key, { ...context, productCode: "caremate" }, envelope));
});

Deno.test("messaging token key configuration fails closed", () => {
  const env = new Map<string, string>([
    ["LIFEMATE_MESSAGING_TOKEN_ENCRYPTION_KEY", "short"],
    ["LIFEMATE_MESSAGING_TOKEN_ENCRYPTION_KEY_VERSION", "1"],
  ]);
  try {
    readMessagingTokenKey((name) => env.get(name));
    throw new Error("expected key configuration failure");
  } catch (error) {
    assertEquals(error instanceof Error, true);
  }
});

Deno.test("messaging token key set supports one previous rotation key", async () => {
  const env = new Map<string, string>([
    ["LIFEMATE_MESSAGING_TOKEN_ENCRYPTION_KEY", "active-messaging-token-encryption-secret-32-bytes-minimum"],
    ["LIFEMATE_MESSAGING_TOKEN_ENCRYPTION_KEY_VERSION", "8"],
    ["LIFEMATE_MESSAGING_TOKEN_PREVIOUS_ENCRYPTION_KEY", "previous-messaging-token-encryption-secret-32-bytes-minimum"],
    ["LIFEMATE_MESSAGING_TOKEN_PREVIOUS_ENCRYPTION_KEY_VERSION", "7"],
  ]);
  const keys = readMessagingTokenKeySet((name) => env.get(name));
  assertEquals(keys.active.keyVersion, 8);
  assertEquals(keys.previous?.keyVersion, 7);

  const token = "fcm-registration-token-encrypted-before-rotation-123456789";
  const tokenHash = await hashMessagingToken(
    "messaging-token-hashing-secret-32-bytes-minimum",
    token,
  );
  const context = {
    accountId: "11111111-1111-4111-8111-111111111111",
    productCode: "wellmate",
    provider: "fcm",
    tokenHash,
  };
  const envelope = await encryptMessagingToken(
    keys.previous!,
    context,
    token,
    new Uint8Array(12).fill(6),
  );
  assertEquals(await decryptMessagingToken(keys.previous!, context, envelope), token);
});

Deno.test("messaging token previous key configuration must be complete and version-distinct", () => {
  const base = new Map<string, string>([
    ["LIFEMATE_MESSAGING_TOKEN_ENCRYPTION_KEY", "active-messaging-token-encryption-secret-32-bytes-minimum"],
    ["LIFEMATE_MESSAGING_TOKEN_ENCRYPTION_KEY_VERSION", "8"],
  ]);
  const missingVersion = new Map(base);
  missingVersion.set(
    "LIFEMATE_MESSAGING_TOKEN_PREVIOUS_ENCRYPTION_KEY",
    "previous-messaging-token-encryption-secret-32-bytes-minimum",
  );
  try {
    readMessagingTokenKeySet((name) => missingVersion.get(name));
    throw new Error("expected incomplete previous key failure");
  } catch (error) {
    assertEquals(error instanceof Error, true);
  }

  const sameVersion = new Map(base);
  sameVersion.set(
    "LIFEMATE_MESSAGING_TOKEN_PREVIOUS_ENCRYPTION_KEY",
    "previous-messaging-token-encryption-secret-32-bytes-minimum",
  );
  sameVersion.set("LIFEMATE_MESSAGING_TOKEN_PREVIOUS_ENCRYPTION_KEY_VERSION", "8");
  try {
    readMessagingTokenKeySet((name) => sameVersion.get(name));
    throw new Error("expected duplicate key version failure");
  } catch (error) {
    assertEquals(error instanceof Error, true);
  }
});
