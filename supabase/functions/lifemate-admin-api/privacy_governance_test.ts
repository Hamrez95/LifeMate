import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  matchLegalDocumentActionPath,
  matchPreferencePurposePath,
  parseLegalDocumentCreate,
  parsePreferencePurposeMutation,
  requestHash,
} from "./privacy_governance.ts";
import { ApiError } from "./validation.ts";

function request(body: unknown): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function legalPayload(overrides: Record<string, unknown> = {}) {
  return {
    purpose: "legal_terms",
    version: "2026.08.v1",
    jurisdiction: "GLOBAL",
    title: "LifeMate Terms of Service",
    documentHash: "a".repeat(64),
    contentUri: "https://mylifemate.ir/legal/terms/2026-08",
    effectiveAtUtc: "2026-09-01T00:00:00.000Z",
    reason: "Publish the reviewed legal document version for registration.",
    ...overrides,
  };
}

Deno.test("legal document draft contract is strict and hash stable", async () => {
  const payload = await parseLegalDocumentCreate(request(legalPayload()));
  assertEquals(payload.purpose, "legal_terms");
  assertEquals(payload.jurisdiction, "GLOBAL");
  assertEquals(payload.effectiveAtUtc, "2026-09-01T00:00:00.000Z");
  const first = await requestHash("privacy.document.create", payload);
  const second = await requestHash("privacy.document.create", payload);
  assertEquals(first, second);
  assert(/^[0-9a-f]{64}$/.test(first));
});

Deno.test("legal governance rejects non-HTTPS content", async () => {
  const error = await assertRejects(
    () => parseLegalDocumentCreate(request(legalPayload({
      contentUri: "http://example.test/terms",
    }))),
    ApiError,
  );
  assertEquals(error.code, "legal_content_uri_invalid");
});

Deno.test("legal governance cannot create an arbitrary consent purpose", async () => {
  const error = await assertRejects(
    () => parseLegalDocumentCreate(request(legalPayload({
      purpose: "caregiver_health_sharing",
    }))),
    ApiError,
  );
  assertEquals(error.code, "legal_purpose_invalid");
});

Deno.test("purpose catalog mutation is bounded and explicit", async () => {
  const payload = await parsePreferencePurposeMutation(request({
    description: "Receive optional product offers by push notification.",
    policyVersion: "v2",
    status: "Active",
    reason: "Clarify promotional wording without changing user consent state.",
  }));
  assertEquals(payload.policyVersion, "v2");
  assertEquals(payload.status, "Active");
});

Deno.test("governance route matchers reject unsafe identifiers", () => {
  const id = "123e4567-e89b-42d3-a456-426614174000";
  assertEquals(
    matchLegalDocumentActionPath(
      `/api/v1/privacy/governance/documents/${id}/publish`,
    ),
    { id, action: "publish" },
  );
  assertEquals(
    matchPreferencePurposePath(
      "/api/v1/privacy/governance/purposes/promotional_push",
    ),
    "promotional_push",
  );
});

Deno.test("admin governance preserves user non-impersonation boundary", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827215500_privacy_governance_admin_contract.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    migration,
    "revoke insert,update,delete on consent.legal_acceptances from lifemate_admin_runtime",
  );
  assertStringIncludes(
    migration,
    "revoke insert,update,delete on consent.data_use_consents from lifemate_admin_runtime",
  );
  assertStringIncludes(
    migration,
    "revoke insert,update,delete on consent.data_use_consent_events from lifemate_admin_runtime",
  );
  assert(!migration.includes("grant insert on consent.legal_acceptances"));
});

Deno.test("acceptance coverage remains aggregate and privacy-minimized", async () => {
  const route = await Deno.readTextFile(
    new URL("./privacy_governance_routes.ts", import.meta.url),
  );
  assertStringIncludes(route, "count(la.account_id)::integer as accepted_accounts");
  assertStringIncludes(route, "accountIdentifiersExposed: false");
  assert(!route.includes("select la.account_id"));
  assert(!route.includes("select la.actor_account_id"));
});
