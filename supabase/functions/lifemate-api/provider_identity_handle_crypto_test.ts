import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  decryptProviderIdentitySubject,
  encryptProviderIdentitySubject,
  providerIdentityHandleDualWriteEnabled,
  readProviderIdentityHandleKey,
} from "../_shared/provider_identity_handle_crypto.ts";

const accountId = "91000000-0000-4000-8000-000000000001";
const otherAccountId = "91000000-0000-4000-8000-000000000002";
const subject = "92000000-0000-4000-8000-000000000001";
const secret = "provider-handle-crypto-test-secret-32-bytes-minimum";
const key = { secret, keyVersion: 3 };
const context = { accountId, provider: "supabase_auth", issuer: "supabase" };

Deno.test("provider identity handle encrypts and authenticates Account context", async () => {
  const envelope = await encryptProviderIdentitySubject(
    key,
    context,
    subject,
    new Uint8Array(12).fill(5),
  );
  assertEquals(envelope.keyVersion, 3);
  assertEquals(envelope.ciphertextB64.includes(subject), false);
  assertEquals(
    await decryptProviderIdentitySubject(key, context, envelope),
    subject,
  );

  await assertRejects(
    () =>
      decryptProviderIdentitySubject(
        key,
        { ...context, accountId: otherAccountId },
        envelope,
      ),
    Error,
    "authentication failed",
  );
  await assertRejects(
    () =>
      decryptProviderIdentitySubject(
        { secret: "different-provider-handle-test-secret-32-bytes-minimum", keyVersion: 3 },
        context,
        envelope,
      ),
    Error,
    "authentication failed",
  );
});

Deno.test("provider handle config is disabled by default and fails closed", () => {
  assertEquals(providerIdentityHandleDualWriteEnabled(() => undefined), false);
  assertThrows(
    () => providerIdentityHandleDualWriteEnabled(() => "maybe"),
    Error,
    "true or false",
  );
  assertThrows(
    () =>
      readProviderIdentityHandleKey((name) =>
        name.endsWith("KEY_VERSION") ? "1" : "short"
      ),
    Error,
    "at least 32",
  );
});
