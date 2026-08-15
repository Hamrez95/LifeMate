import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  createIdentityResolver,
  readIdentityLookupMode,
} from "./identity_resolver.ts";

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
        identityLinkKey: {
          secret: "0123456789abcdef0123456789abcdef",
          keyVersion: 1,
        },
      }),
    Error,
    "requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true",
  );
  assertThrows(
    () =>
      createIdentityResolver("postgres://unused:unused@localhost:5432/unused", {
        mode: "token-only",
        dualWriteEnabled: false,
        identityLinkKey: {
          secret: "0123456789abcdef0123456789abcdef",
          keyVersion: 1,
        },
      }),
    Error,
    "requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true",
  );
});

Deno.test("legacy mode does not require the external identity-link key", () => {
  const resolver = createIdentityResolver(
    "postgres://unused:unused@localhost:5432/unused",
    {
      mode: "legacy",
      readEnvironment: () => undefined,
    },
  );
  assertEquals(resolver.lookupMode, "legacy");
});
