import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  deriveIdentityLinkToken,
  readIdentityLinkKeyFromEnvironment,
} from "./identity_link_token.ts";

const secret = "0123456789abcdef0123456789abcdef";
const input = {
  provider: "supabase_auth",
  issuer: "supabase",
  subject: "11111111-2222-4333-8444-555555555555",
  keyVersion: 1,
};

Deno.test("identity link token is deterministic and opaque", async () => {
  const first = await deriveIdentityLinkToken(secret, input);
  const second = await deriveIdentityLinkToken(secret, input);

  assertEquals(first, second);
  assertEquals(first.length, 64);
  assert(/^[0-9a-f]{64}$/.test(first));
  assert(!first.includes(input.subject));
});

Deno.test("identity link token is scoped by provider issuer key and version", async () => {
  const baseline = await deriveIdentityLinkToken(secret, input);
  assertNotEquals(
    baseline,
    await deriveIdentityLinkToken(secret, { ...input, provider: "google" }),
  );
  assertNotEquals(
    baseline,
    await deriveIdentityLinkToken(secret, {
      ...input,
      issuer: "https://accounts.google.com",
    }),
  );
  assertNotEquals(
    baseline,
    await deriveIdentityLinkToken(secret, { ...input, keyVersion: 2 }),
  );
  assertNotEquals(
    baseline,
    await deriveIdentityLinkToken(
      "abcdef0123456789abcdef0123456789",
      input,
    ),
  );
});

Deno.test("identity link token rejects weak or malformed inputs", async () => {
  await assertRejects(
    () => deriveIdentityLinkToken("too-short", input),
    Error,
    "at least 32 UTF-8 bytes",
  );
  await assertRejects(
    () => deriveIdentityLinkToken(secret, { ...input, subject: "" }),
    Error,
    "subject is invalid",
  );
  await assertRejects(
    () => deriveIdentityLinkToken(secret, { ...input, keyVersion: 0 }),
    Error,
    "key version is invalid",
  );
});

Deno.test("identity link key loader fails closed and never reads database state", () => {
  const previousKey = Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY");
  const previousVersion = Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY_VERSION");
  try {
    Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY");
    Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY_VERSION");
    assertThrows(
      () => readIdentityLinkKeyFromEnvironment(),
      Error,
      "external runtime secret",
    );

    Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", secret);
    Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY_VERSION", "7");
    assertEquals(readIdentityLinkKeyFromEnvironment(), {
      secret,
      keyVersion: 7,
    });
  } finally {
    if (previousKey == null) Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY");
    else Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", previousKey);
    if (previousVersion == null) {
      Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY_VERSION");
    } else {
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY_VERSION", previousVersion);
    }
  }
});
