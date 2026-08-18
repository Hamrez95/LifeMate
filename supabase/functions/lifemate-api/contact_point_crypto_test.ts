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
