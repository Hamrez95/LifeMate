import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  decryptMessagingToken,
  encryptMessagingToken,
  hashMessagingToken,
  readMessagingTokenKey,
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
