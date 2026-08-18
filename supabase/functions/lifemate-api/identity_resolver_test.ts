import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  createIdentityResolver,
  readIdentityLookupMode,
} from "./identity_resolver.ts";

const activeKey = {
  secret: "0123456789abcdef0123456789abcdef",
  keyVersion: 8,
};
const previousKey = {
  secret: "abcdef0123456789abcdef0123456789",
  keyVersion: 7,
};

Deno.test("identity lookup mode defaults to legacy and is strict", () => {
  assertEquals(readIdentityLookupMode(() => undefined), "legacy");
  assertEquals(
    readIdentityLookupMode((name) =>
      name === "LIFEMATE_IDENTITY_LINK_LOOKUP_MODE" ? " prefer-token " : null
    ),
    "prefer-token",
  );
  assertEquals(
    readIdentityLookupMode((name) =>
      name === "LIFEMATE_IDENTITY_LINK_LOOKUP_MODE" ? "TOKEN-ONLY" : null
    ),
    "token-only",
  );
  assertThrows(
    () =>
      readIdentityLookupMode((name) =>
        name === "LIFEMATE_IDENTITY_LINK_LOOKUP_MODE"
          ? "token_if_available"
          : null
      ),
    Error,
    "must be legacy, prefer-token, or token-only",
  );
});

Deno.test("token lookup cannot start while dual-write is disabled", () => {
  assertThrows(
    () =>
      createIdentityResolver("postgres://unused:unused@localhost:5432/unused", {
        mode: "prefer-token",
        dualWriteEnabled: false,
        identityLinkKey: activeKey,
      }),
    Error,
    "requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true",
  );
  assertThrows(
    () =>
      createIdentityResolver("postgres://unused:unused@localhost:5432/unused", {
        mode: "token-only",
        dualWriteEnabled: false,
        identityLinkKey: activeKey,
      }),
    Error,
    "requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true",
  );
});

Deno.test("legacy mode does not require active or previous identity-link keys", () => {
  const resolver = createIdentityResolver(
    "postgres://unused:unused@localhost:5432/unused",
    {
      mode: "legacy",
      readEnvironment: () => undefined,
    },
  );
  assertEquals(resolver.lookupMode, "legacy");
});

Deno.test("token lookup accepts one previous key with a distinct version", () => {
  const resolver = createIdentityResolver(
    "postgres://unused:unused@localhost:5432/unused",
    {
      mode: "token-only",
      dualWriteEnabled: true,
      identityLinkKey: activeKey,
      previousIdentityLinkKey: previousKey,
    },
  );
  assertEquals(resolver.lookupMode, "token-only");
});

Deno.test("token lookup rejects equal active and previous key versions", () => {
  assertThrows(
    () =>
      createIdentityResolver("postgres://unused:unused@localhost:5432/unused", {
        mode: "token-only",
        dualWriteEnabled: true,
        identityLinkKey: activeKey,
        previousIdentityLinkKey: {
          secret: previousKey.secret,
          keyVersion: activeKey.keyVersion,
        },
      }),
    Error,
    "must differ from the active key version",
  );
});

Deno.test("partial previous-key environment fails before database access", () => {
  const readEnvironment = (name: string) => {
    if (name === "LIFEMATE_IDENTITY_LINK_KEY") return activeKey.secret;
    if (name === "LIFEMATE_IDENTITY_LINK_KEY_VERSION") return "8";
    if (name === "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY") {
      return previousKey.secret;
    }
    return undefined;
  };
  assertThrows(
    () =>
      createIdentityResolver("postgres://unused:unused@localhost:5432/unused", {
        mode: "token-only",
        dualWriteEnabled: true,
        readEnvironment,
      }),
    Error,
    "must be configured together",
  );
});
