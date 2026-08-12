import { assertEquals, assertThrows } from "jsr:@std/assert@1";

import { readVerifiedSessionClaims, requireAal2 } from "./auth.ts";
import { ApiError } from "./validation.ts";

function encoded(value: Record<string, unknown>): string {
  return btoa(JSON.stringify(value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function token(subject: string, aal: string): string {
  return `${encoded({ alg: "none", typ: "JWT" })}.${encoded({ sub: subject, aal })}.signature`;
}

Deno.test("reads AAL only from the token already verified for the same user", () => {
  const subject = "11111111-1111-4111-8111-111111111111";
  assertEquals(readVerifiedSessionClaims(token(subject, "aal2"), subject), {
    subject,
    aal: "aal2",
  });
});

Deno.test("rejects a token subject that differs from the verified Auth user", () => {
  assertThrows(
    () =>
      readVerifiedSessionClaims(
        token("11111111-1111-4111-8111-111111111111", "aal2"),
        "22222222-2222-4222-8222-222222222222",
      ),
    ApiError,
  );
});

Deno.test("Admin access requires AAL2", () => {
  assertThrows(
    () =>
      requireAal2({
        providerSubject: "11111111-1111-4111-8111-111111111111",
        email: null,
        aal: "aal1",
      }),
    ApiError,
  );
});
