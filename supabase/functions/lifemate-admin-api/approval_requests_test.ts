import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  hashCreateApprovalRequest,
  matchApprovalDecisionPath,
  matchApprovalRequestPath,
  parseCreateApprovalRequest,
  parseDecideApprovalRequest,
} from "./approval_requests.ts";
import { ApiError } from "./validation.ts";

function request(body: unknown): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("approval request payload is bounded and hashes canonically", async () => {
  const left = await parseCreateApprovalRequest(request({
    requestType: "commerce.entitlement.adjust",
    targetType: "account",
    targetId: "account-opaque-id",
    before: { expiresAt: "2026-09-01", plan: "plus" },
    delta: { days: 30 },
    after: { plan: "plus", expiresAt: "2026-10-01" },
    reason: "Support compensation approved for review.",
  }));
  const right = await parseCreateApprovalRequest(request({
    targetId: "account-opaque-id",
    targetType: "account",
    requestType: "commerce.entitlement.adjust",
    after: { expiresAt: "2026-10-01", plan: "plus" },
    delta: { days: 30 },
    before: { plan: "plus", expiresAt: "2026-09-01" },
    reason: "Support compensation approved for review.",
  }));
  assertEquals(
    await hashCreateApprovalRequest(left),
    await hashCreateApprovalRequest(right),
  );
});

Deno.test("generic approval state rejects sensitive payload fields", async () => {
  for (
    const unsafe of [
      { healthStatus: "private" },
      { medicationName: "private" },
      { patientNote: "private" },
      { phone: "+000000000" },
      { secretToken: "private" },
    ]
  ) {
    const error = await assertRejects(
      () =>
        parseCreateApprovalRequest(request({
          requestType: "commerce.entitlement.adjust",
          targetType: "account",
          targetId: "opaque-account-id",
          before: {},
          delta: unsafe,
          after: {},
          reason: "Request a reviewed business-state adjustment.",
        })),
      ApiError,
    );
    assertEquals(error.code, "approval_state_sensitive");
  }
});

Deno.test("generic approval targets must be opaque internal identifiers", async () => {
  for (
    const targetId of [
      "+989121234567",
      "09121234567",
      "person@example.com",
      "free form target",
    ]
  ) {
    const error = await assertRejects(
      () =>
        parseCreateApprovalRequest(request({
          requestType: "commerce.entitlement.adjust",
          targetType: "account",
          targetId,
          before: {},
          delta: { days: 1 },
          after: {},
          reason:
            "Reject contact or free-form identifiers from ledger targets.",
        })),
      ApiError,
    );
    assertEquals(error.code, "approval_target_invalid");
  }
});

Deno.test("approval decisions require optimistic version and explicit reason", async () => {
  const parsed = await parseDecideApprovalRequest(
    request({
      expectedVersion: 3,
      reason: "Reviewed against the requested business correction.",
    }),
    "approve",
  );
  assertEquals(parsed.expectedVersion, 3);
  assertEquals(parsed.decision, "approve");

  const error = await assertRejects(
    () =>
      parseDecideApprovalRequest(
        request({ expectedVersion: 0, reason: "Long enough reason text." }),
        "reject",
      ),
    ApiError,
  );
  assertEquals(error.code, "approval_version_invalid");
});

Deno.test("approval route matching is explicit", () => {
  const id = "123e4567-e89b-12d3-a456-426614174000";
  assertEquals(
    matchApprovalRequestPath(`/api/v1/operations/approval-requests/${id}`),
    id,
  );
  assertEquals(
    matchApprovalDecisionPath(
      `/api/v1/operations/approval-requests/${id}/actions/approve`,
    ),
    { id, decision: "approve" },
  );
  assertEquals(
    matchApprovalDecisionPath(
      `/api/v1/operations/approval-requests/${id}/actions/reject`,
    ),
    { id, decision: "reject" },
  );
});

Deno.test("approval ledger is server-only, purpose-scoped and self-approval defaults denied", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827013000_admin_approval_adjustment_ledger.sql",
      import.meta.url,
    ),
  );
  const rls = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827013100_admin_approval_runtime_rls.sql",
      import.meta.url,
    ),
  );
  const bounds = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827013200_admin_approval_payload_bounds.sql",
      import.meta.url,
    ),
  );
  const privacy = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827013300_admin_approval_privacy_hardening.sql",
      import.meta.url,
    ),
  );
  const routes = await Deno.readTextFile(
    new URL("./approval_requests_routes.ts", import.meta.url),
  );
  const service = await Deno.readTextFile(
    new URL("./approval_requests_service.ts", import.meta.url),
  );

  assertStringIncludes(
    migration,
    "self_approval_allowed boolean not null default false",
  );
  assertStringIncludes(migration, "admin.approval_actor_is_eligible_approver");
  assertStringIncludes(migration, "v_policy.approval_permission");
  assertStringIncludes(migration, "v_policy.execution_permission");
  assertStringIncludes(migration, "not v_policy.self_approval_allowed");
  assertStringIncludes(migration, "consume_approval_request");
  assertStringIncludes(
    migration,
    "Must be called inside the same database transaction as the purpose-specific mutation",
  );
  assertStringIncludes(rls, "lifemate_admin_runtime_rw");
  assertStringIncludes(bounds, "octet_length(before_json::text) <= 16384");
  assertStringIncludes(
    bounds,
    "raw health/contact/secret payloads are prohibited",
  );
  assertStringIncludes(privacy, "approval_state_has_forbidden_keys");
  assertStringIncludes(privacy, "ck_admin_approval_target_opaque");
  assertStringIncludes(
    migration,
    "revoke all on table admin.approval_requests from public,anon,authenticated",
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin,"operations.approval.read")',
  );
  assert(!routes.includes("service_role"));
  assert(!service.includes("supabase.from"));
});

Deno.test("generic approval API cannot execute a child-domain mutation by itself", async () => {
  const routes = await Deno.readTextFile(
    new URL("./approval_requests_routes.ts", import.meta.url),
  );
  assert(!routes.includes("actions/execute"));
  assert(!routes.includes("consume_approval_request"));
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827013000_admin_approval_adjustment_ledger.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    migration,
    "create or replace function admin.consume_approval_request",
  );
  assertStringIncludes(
    migration,
    "if not admin.account_has_permission(p_actor_account_id,v_policy.execution_permission)",
  );
});
