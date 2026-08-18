import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  createAdminIdentityResolver,
  deriveAdminIdentityLinkToken,
  readAdminIdentityLinkKeySet,
  readAdminIdentityLookupMode,
} from "./identity_resolution.ts";
import { ApiError } from "./validation.ts";

const secret = "admin-identity-link-test-secret-32-bytes-minimum";
const previousSecret = "admin-identity-link-previous-secret-32-bytes";
const accountId = "91000000-0000-4000-8000-000000000001";
const otherAccountId = "91000000-0000-4000-8000-000000000002";

Deno.test("Admin identity lookup mode defaults and validates", () => {
  assertEquals(readAdminIdentityLookupMode(() => undefined), "legacy");
  assertEquals(
    readAdminIdentityLookupMode((name) =>
      name === "LIFEMATE_IDENTITY_LINK_LOOKUP_MODE" ? "prefer-token" : undefined
    ),
    "prefer-token",
  );
  assertEquals(
    readAdminIdentityLookupMode((name) =>
      name === "LIFEMATE_ADMIN_IDENTITY_LINK_LOOKUP_MODE"
        ? "token-only"
        : "legacy"
    ),
    "token-only",
  );
  assertThrows(
    () => readAdminIdentityLookupMode(() => "unsafe"),
    Error,
    "legacy, prefer-token, or token-only",
  );
});

Deno.test("Admin identity token uses the Core canonical HMAC message", async () => {
  const token = await deriveAdminIdentityLinkToken(secret, "auth-subject-1", 7);
  assertEquals(token.length, 64);
  assertEquals(/^[0-9a-f]{64}$/.test(token), true);
  assertEquals(
    token,
    await deriveAdminIdentityLinkToken(secret, "auth-subject-1", 7),
  );
});

Deno.test("Admin keyset accepts one previous key and rejects partial overlap", () => {
  const configured = (name: string) => {
    if (name === "LIFEMATE_IDENTITY_LINK_KEY") return secret;
    if (name === "LIFEMATE_IDENTITY_LINK_KEY_VERSION") return "8";
    if (name === "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY") {
      return previousSecret;
    }
    if (name === "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION") return "7";
    return undefined;
  };
  assertEquals(readAdminIdentityLinkKeySet(configured), {
    active: { secret, keyVersion: 8 },
    previous: { secret: previousSecret, keyVersion: 7 },
  });

  assertThrows(
    () =>
      readAdminIdentityLinkKeySet((name) => {
        if (name === "LIFEMATE_IDENTITY_LINK_KEY") return secret;
        if (name === "LIFEMATE_IDENTITY_LINK_KEY_VERSION") return "8";
        if (name === "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY") {
          return previousSecret;
        }
        return undefined;
      }),
    Error,
    "must be configured together",
  );
});

Deno.test("token-only never calls raw provider-subject lookup", async () => {
  let legacyCalls = 0;
  const resolver = createAdminIdentityResolver("postgres://unused", {
    mode: "token-only",
    dualWriteEnabled: true,
    identityLinkKey: { secret, keyVersion: 1 },
    lookupToken:
      async () => [{ account_id: accountId, account_status: "Active" }],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [];
    },
  });
  assertEquals(await resolver.resolveAccountId("auth-subject-1"), accountId);
  assertEquals(legacyCalls, 0);
});

Deno.test("token-only reads the previous Core key during bounded rotation", async () => {
  let legacyCalls = 0;
  const resolver = createAdminIdentityResolver("postgres://unused", {
    mode: "token-only",
    dualWriteEnabled: true,
    identityLinkKey: { secret, keyVersion: 8 },
    previousIdentityLinkKey: { secret: previousSecret, keyVersion: 7 },
    lookupToken: async (_token, version) =>
      version === 7
        ? [{ account_id: accountId, account_status: "Active" }]
        : [],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ account_id: otherAccountId }];
    },
  });
  assertEquals(await resolver.resolveAccountId("auth-subject-1"), accountId);
  assertEquals(legacyCalls, 0);
});

Deno.test("Admin rotation conflict fails closed without raw fallback", async () => {
  let legacyCalls = 0;
  const resolver = createAdminIdentityResolver("postgres://unused", {
    mode: "prefer-token",
    dualWriteEnabled: true,
    identityLinkKey: { secret, keyVersion: 8 },
    previousIdentityLinkKey: { secret: previousSecret, keyVersion: 7 },
    lookupToken: async (_token, version) =>
      version === 8
        ? [{ account_id: accountId, account_status: "Active" }]
        : [{ account_id: otherAccountId, account_status: "Active" }],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ account_id: accountId }];
    },
  });
  const error = await assertRejects(
    () => resolver.resolveAccountId("auth-subject-1"),
    ApiError,
  );
  assertEquals(error.status, 409);
  assertEquals(error.code, "identity_token_rotation_conflict");
  assertEquals(legacyCalls, 0);
});

Deno.test("token-only fails closed when canonical token is missing", async () => {
  let legacyCalls = 0;
  const resolver = createAdminIdentityResolver("postgres://unused", {
    mode: "token-only",
    dualWriteEnabled: true,
    identityLinkKey: { secret, keyVersion: 1 },
    lookupToken: async () => [],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ account_id: accountId }];
    },
  });
  const error = await assertRejects(
    () => resolver.resolveAccountId("auth-subject-1"),
    ApiError,
  );
  assertEquals(error.status, 403);
  assertEquals(error.code, "lifemate_account_required");
  assertEquals(legacyCalls, 0);
});

Deno.test("prefer-token falls back only when no canonical token exists", async () => {
  let legacyCalls = 0;
  const resolver = createAdminIdentityResolver("postgres://unused", {
    mode: "prefer-token",
    dualWriteEnabled: true,
    identityLinkKey: { secret, keyVersion: 1 },
    lookupToken: async () => [],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ account_id: accountId }];
    },
  });
  assertEquals(await resolver.resolveAccountId("auth-subject-1"), accountId);
  assertEquals(legacyCalls, 1);
});

Deno.test("broken token mapping never falls back to raw identity", async () => {
  let legacyCalls = 0;
  const resolver = createAdminIdentityResolver("postgres://unused", {
    mode: "prefer-token",
    dualWriteEnabled: true,
    identityLinkKey: { secret, keyVersion: 1 },
    lookupToken:
      async () => [{ account_id: accountId, account_status: "Disabled" }],
    lookupLegacy: async () => {
      legacyCalls += 1;
      return [{ account_id: accountId }];
    },
  });
  const error = await assertRejects(
    () => resolver.resolveAccountId("auth-subject-1"),
    ApiError,
  );
  assertEquals(error.status, 403);
  assertEquals(legacyCalls, 0);
});

Deno.test("non-legacy Admin lookup refuses missing dual-write gate", () => {
  assertThrows(
    () =>
      createAdminIdentityResolver("postgres://unused", {
        mode: "token-only",
        dualWriteEnabled: false,
        identityLinkKey: { secret, keyVersion: 1 },
      }),
    Error,
    "LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true",
  );
});
