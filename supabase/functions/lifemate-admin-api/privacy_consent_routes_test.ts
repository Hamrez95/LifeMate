import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1.0.14";
import { createPrivacyConsentRouteHandler, parseDirectoryQuery } from "./privacy_consent_routes.ts";
import { ApiError } from "./validation.ts";

Deno.test("privacy directory query is bounded and typed", () => {
  assertEquals(
    parseDirectoryQuery(
      new URL("https://example.test/api/v1/privacy/documents?page=2&pageSize=25&q=privacy&status=Published"),
      "document",
    ),
    { q: "privacy", status: "Published", page: 2, pageSize: 25 },
  );
  assertThrows(
    () => parseDirectoryQuery(new URL("https://example.test/api/v1/privacy/documents?status=Deleted"), "document"),
    ApiError,
  );
  assertThrows(
    () => parseDirectoryQuery(new URL("https://example.test/api/v1/privacy/preferences?pageSize=1000"), "preference"),
    ApiError,
  );
});

Deno.test("privacy routes fail before database access without permission", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://127.0.0.1:1/unused");
  const context = {
    request: new Request("https://example.test/api/v1/privacy/acceptances"),
    path: "/api/v1/privacy/acceptances",
    accountId: "11111111-1111-4111-8111-111111111111",
    admin: {
      accountId: "11111111-1111-4111-8111-111111111111",
      roles: ["support"],
      permissions: ["support.read"],
    },
    correlationId: "22222222-2222-4222-8222-222222222222",
    origin: null,
  };
  await assertRejects(
    () => handler(context),
    ApiError,
    "Administrative permission is required",
  );
});

Deno.test("privacy retirement requires manage permission before payload/database work", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://127.0.0.1:1/unused");
  await assertRejects(
    () => handler({
      request: new Request(
        "https://example.test/api/v1/privacy/documents/33333333-3333-4333-8333-333333333333/retire",
        { method: "POST", body: "not-json" },
      ),
      path: "/api/v1/privacy/documents/33333333-3333-4333-8333-333333333333/retire",
      accountId: "11111111-1111-4111-8111-111111111111",
      admin: {
        accountId: "11111111-1111-4111-8111-111111111111",
        roles: ["founder"],
        permissions: ["privacy.consent.read"],
      },
      correlationId: "22222222-2222-4222-8222-222222222222",
      origin: null,
    }),
    ApiError,
    "Administrative permission is required",
  );
});
