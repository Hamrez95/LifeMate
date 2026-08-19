import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  decryptProviderIdentitySubject,
  encryptProviderIdentitySubject,
  providerIdentityHandleDualWriteEnabled,
  readProviderIdentityHandleKey,
  readProviderIdentityHandleKeySet,
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
        {
          secret: "different-provider-handle-test-secret-32-bytes-minimum",
          keyVersion: 3,
        },
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

Deno.test("provider handle keyset supports one bounded previous key", () => {
  const activeSecret = "provider-handle-active-test-secret-32-bytes-minimum";
  const previousSecret =
    "provider-handle-previous-test-secret-32-bytes-minimum";
  const values: Record<string, string> = {
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY: activeSecret,
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION: "10",
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY: previousSecret,
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION: "9",
  };
  assertEquals(readProviderIdentityHandleKeySet((name) => values[name]), {
    active: { secret: activeSecret, keyVersion: 10 },
    previous: { secret: previousSecret, keyVersion: 9 },
  });
});

Deno.test("provider handle keyset rejects partial or equal-version overlap", () => {
  const activeSecret = "provider-handle-active-test-secret-32-bytes-minimum";
  const previousSecret =
    "provider-handle-previous-test-secret-32-bytes-minimum";
  const active = {
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY: activeSecret,
    LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION: "10",
  };
  const read = (values: Record<string, string>) => (name: string) =>
    values[name];

  assertThrows(
    () =>
      readProviderIdentityHandleKeySet(read({
        ...active,
        LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY: previousSecret,
      })),
    Error,
    "must be configured together",
  );
  assertThrows(
    () =>
      readProviderIdentityHandleKeySet(read({
        ...active,
        LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION: "9",
      })),
    Error,
    "must be configured together",
  );
  assertThrows(
    () =>
      readProviderIdentityHandleKeySet(read({
        ...active,
        LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY: previousSecret,
        LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION: "10",
      })),
    Error,
    "must differ from the active key version",
  );
});
