import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  contactPointDualWriteEnabled,
  decryptContactPoint,
  encryptContactPoint,
  hashContactPoint,
  normalizeContactPoint,
  readContactEncryptionKey,
  readContactEncryptionKeySet,
} from "../_shared/contact_point_crypto.ts";

const accountId = "91000000-0000-4000-8000-000000000001";
const otherAccountId = "91000000-0000-4000-8000-000000000002";
const hashSecret = "contact-point-hash-test-secret-32-bytes-minimum";
const encryptionKey = {
  secret: "contact-point-envelope-test-secret-32-bytes-minimum",
  keyVersion: 4,
};

Deno.test("ContactPoint normalization and HMAC are stable and domain-separated", async () => {
  assertEquals(
    normalizeContactPoint("Email", " User@Example.COM "),
    "user@example.com",
  );
  assertEquals(
    normalizeContactPoint("Phone", "+98 (912) 123-4567"),
    "+989121234567",
  );

  const emailHash = await hashContactPoint(
    hashSecret,
    "Email",
    "User@Example.COM",
  );
  const sameEmailHash = await hashContactPoint(
    hashSecret,
    "Email",
    " user@example.com ",
  );
  const phoneHash = await hashContactPoint(
    hashSecret,
    "Phone",
    "+989121234567",
  );
  assertEquals(emailHash, sameEmailHash);
  assertEquals(emailHash.length, 64);
  assertEquals(/^[0-9a-f]{64}$/.test(emailHash), true);
  assertNotEquals(emailHash, phoneHash);
  assertEquals(emailHash.includes("user@example.com"), false);
});

Deno.test("ContactPoint envelope is bound to Account, kind, hash and key", async () => {
  const normalized = normalizeContactPoint("Email", "User@Example.COM");
  const normalizedValueHash = await hashContactPoint(
    hashSecret,
    "Email",
    normalized,
  );
  const envelope = await encryptContactPoint(
    encryptionKey,
    { accountId, kind: "Email", normalizedValueHash },
    normalized,
    new Uint8Array(12).fill(9),
  );
  assertEquals(envelope.ciphertextB64.includes(normalized), false);
  assertEquals(
    await decryptContactPoint(
      encryptionKey,
      { accountId, kind: "Email", normalizedValueHash },
      envelope,
    ),
    normalized,
  );

  await assertRejects(
    () =>
      decryptContactPoint(
        encryptionKey,
        { accountId: otherAccountId, kind: "Email", normalizedValueHash },
        envelope,
      ),
    Error,
    "authentication failed",
  );
  await assertRejects(
    () =>
      decryptContactPoint(
        {
          secret: "different-contact-point-envelope-key-32-bytes-minimum",
          keyVersion: 4,
        },
        { accountId, kind: "Email", normalizedValueHash },
        envelope,
      ),
    Error,
    "authentication failed",
  );
});

Deno.test("ContactPoint dual-write config is disabled by default and fail-closed", () => {
  assertEquals(contactPointDualWriteEnabled(() => undefined), false);
  assertThrows(
    () => contactPointDualWriteEnabled(() => "maybe"),
    Error,
    "true or false",
  );
  assertThrows(
    () =>
      readContactEncryptionKey((name) =>
        name.endsWith("KEY_VERSION") ? "1" : "short"
      ),
    Error,
    "at least 32",
  );
});

Deno.test("ContactPoint encryption keyset supports one bounded previous key", () => {
  const activeSecret = "contact-active-envelope-key-32-bytes-minimum";
  const previousSecret =
    "contact-previous-envelope-key-32-bytes-minimum";
  const readEnvironment = (name: string) => {
    if (name === "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY") {
      return activeSecret;
    }
    if (name === "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION") {
      return "12";
    }
    if (name === "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY") {
      return previousSecret;
    }
    if (
      name === "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION"
    ) {
      return "11";
    }
    return undefined;
  };
  assertEquals(readContactEncryptionKeySet(readEnvironment), {
    active: { secret: activeSecret, keyVersion: 12 },
    previous: { secret: previousSecret, keyVersion: 11 },
  });
});

Deno.test("ContactPoint encryption keyset rejects unsafe previous-key overlap", () => {
  const activeSecret = "contact-active-envelope-key-32-bytes-minimum";
  const previousSecret =
    "contact-previous-envelope-key-32-bytes-minimum";
  const read = (values: Record<string, string>) => (name: string) => values[name];
  const active = {
    LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY: activeSecret,
    LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION: "12",
  };

  assertThrows(
    () =>
      readContactEncryptionKeySet(read({
        ...active,
        LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY: previousSecret,
      })),
    Error,
    "must be configured together",
  );
  assertThrows(
    () =>
      readContactEncryptionKeySet(read({
        ...active,
        LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION: "11",
      })),
    Error,
    "must be configured together",
  );
  assertThrows(
    () =>
      readContactEncryptionKeySet(read({
        ...active,
        LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY: "short",
        LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION: "11",
      })),
    Error,
    "at least 32",
  );
  assertThrows(
    () =>
      readContactEncryptionKeySet(read({
        ...active,
        LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY: previousSecret,
        LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION: "12",
      })),
    Error,
    "must differ from the active key version",
  );
});
