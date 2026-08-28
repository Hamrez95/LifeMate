import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  createPrivacyConsentRouteHandler,
  parseDirectoryQuery,
} from "./privacy_consent_routes.ts";
import { ApiError } from "./validation.ts";

const ACCOUNT_ID = "11111111-1111-4111-8111-111111111111";
const CORRELATION_ID = "22222222-2222-4222-8222-222222222222";

Deno.test("privacy directory query is bounded and typed", () => {
  assertEquals(
    parseDirectoryQuery(
      new URL(
        "https://example.test/api/v1/privacy/documents?page=2&pageSize=25&q=privacy&status=Active",
      ),
      "document",
    ),
    { q: "privacy", status: "Active", page: 2, pageSize: 25 },
  );
  assertEquals(
    parseDirectoryQuery(
      new URL("https://example.test/api/v1/privacy/consents?status=Revoked"),
      "consent",
    ).status,
    "Revoked",
  );
  assertThrows(
    () =>
      parseDirectoryQuery(
        new URL("https://example.test/api/v1/privacy/documents?status=Deleted"),
        "document",
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseDirectoryQuery(
        new URL("https://example.test/api/v1/privacy/preferences?pageSize=1000"),
        "preference",
      ),
    ApiError,
  );
});

Deno.test("privacy routes fail before database access without permission", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://127.0.0.1:1/unused");
  await assertRejects(
    () =>
      handler({
        request: new Request("https://example.test/api/v1/privacy/acceptances"),
        path: "/api/v1/privacy/acceptances",
        accountId: ACCOUNT_ID,
        admin: { accountId: ACCOUNT_ID, roles: ["support"], permissions: ["support.read"] },
        correlationId: CORRELATION_ID,
        origin: null,
      }),
    ApiError,
    "Administrative permission is required",
  );
});

Deno.test("privacy retirement requires manage permission before payload/database work", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://127.0.0.1:1/unused");
  await assertRejects(
    () =>
      handler({
        request: new Request(
          "https://example.test/api/v1/privacy/documents/33333333-3333-4333-8333-333333333333/retire",
          { method: "POST", body: "not-json" },
        ),
        path: "/api/v1/privacy/documents/33333333-3333-4333-8333-333333333333/retire",
        accountId: ACCOUNT_ID,
        admin: { accountId: ACCOUNT_ID, roles: ["founder"], permissions: ["privacy.consent.read"] },
        correlationId: CORRELATION_ID,
        origin: null,
      }),
    ApiError,
    "Administrative permission is required",
  );
});

Deno.test("privacy writes require Idempotency-Key before database work", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://127.0.0.1:1/unused");
  await assertRejects(
    () =>
      handler({
        request: new Request("https://example.test/api/v1/privacy/documents", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            purpose: "privacy_notice",
            version: "v2",
            jurisdiction: "GLOBAL",
            title: "Privacy notice",
            documentHash: "a".repeat(64),
            contentUri: "https://example.test/privacy/v2",
            effectiveAtUtc: "2026-09-01T00:00:00.000Z",
            reasonCode: "new_version",
          }),
        }),
        path: "/api/v1/privacy/documents",
        accountId: ACCOUNT_ID,
        admin: {
          accountId: ACCOUNT_ID,
          roles: ["founder"],
          permissions: ["privacy.consent.read", "privacy.consent.manage"],
        },
        correlationId: CORRELATION_ID,
        origin: null,
      }),
    ApiError,
    "Idempotency-Key",
  );
});

Deno.test("purpose administration cannot mutate a user's preference choice", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://127.0.0.1:1/unused");
  await assertRejects(
    () =>
      handler({
        request: new Request("https://example.test/api/v1/privacy/purposes/promotional_sms", {
          method: "POST",
          headers: { "content-type": "application/json", "Idempotency-Key": "privacy-test-1234" },
          body: JSON.stringify({
            expectedUpdatedAt: "2026-08-28T00:00:00.000Z",
            description: "Optional SMS messages",
            policyVersion: "v2",
            status: "Active",
            reasonCode: "wording_update",
            enabled: true,
          }),
        }),
        path: "/api/v1/privacy/purposes/promotional_sms",
        accountId: ACCOUNT_ID,
        admin: {
          accountId: ACCOUNT_ID,
          roles: ["founder"],
          permissions: ["privacy.consent.read", "privacy.consent.manage"],
        },
        correlationId: CORRELATION_ID,
        origin: null,
      }),
    ApiError,
    "unsupported fields",
  );
});

Deno.test("document creation rejects non-HTTPS content before database work", async () => {
  const handler = createPrivacyConsentRouteHandler("postgres://127.0.0.1:1/unused");
  await assertRejects(
    () =>
      handler({
        request: new Request("https://example.test/api/v1/privacy/documents", {
          method: "POST",
          headers: { "content-type": "application/json", "Idempotency-Key": "privacy-test-5678" },
          body: JSON.stringify({
            purpose: "legal_terms",
            version: "v3",
            jurisdiction: "GLOBAL",
            title: "Legal terms",
            documentHash: "b".repeat(64),
            contentUri: "http://example.test/terms/v3",
            reasonCode: "new_version",
          }),
        }),
        path: "/api/v1/privacy/documents",
        accountId: ACCOUNT_ID,
        admin: {
          accountId: ACCOUNT_ID,
          roles: ["founder"],
          permissions: ["privacy.consent.read", "privacy.consent.manage"],
        },
        correlationId: CORRELATION_ID,
        origin: null,
      }),
    ApiError,
    "contentUri must use HTTPS",
  );
});
