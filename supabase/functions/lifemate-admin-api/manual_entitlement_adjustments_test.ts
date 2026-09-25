import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  hashManualEntitlementPayload,
  parseManualEntitlementPayload,
} from "./manual_entitlement_adjustments.ts";
import { ApiError } from "./validation.ts";

const accountId = "123e4567-e89b-42d3-a456-426614174000";
const targetId = "223e4567-e89b-42d3-a456-426614174000";
const entitlementId = "323e4567-e89b-42d3-a456-426614174000";

function request(body: Record<string, unknown>): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("Grant supports Product/Offer and stable reference-based AddMonths", async () => {
  const payload = await parseManualEntitlementPayload(
    request({
      subjectAccountId: accountId,
      targetType: "Product",
      targetId,
      operation: "Grant",
      scheduleMode: "AddMonths",
      scheduleAmount: 3,
      referenceAtUtc: "2026-08-27T03:00:00.000Z",
      reason:
        "Founder grants a three month entitlement after an approved support correction.",
    }),
    { requireReference: true },
  );
  assertEquals(payload.operation, "Grant");
  assertEquals(payload.referenceAtUtc, "2026-08-27T03:00:00.000Z");
  const first = await hashManualEntitlementPayload(payload);
  const second = await hashManualEntitlementPayload(payload);
  assertEquals(first, second);
  assert(/^[0-9a-f]{64}$/.test(first));
});

Deno.test("existing entitlement operations require exact entitlement version", async () => {
  const error = await assertRejects(
    () =>
      parseManualEntitlementPayload(
        request({
          subjectAccountId: accountId,
          targetType: "Offer",
          targetId,
          entitlementId,
          operation: "Extend",
          scheduleMode: "AddDays",
          scheduleAmount: 30,
          referenceAtUtc: "2026-08-27T03:00:00.000Z",
          reason:
            "Extend a selected entitlement rather than mutating all matching features.",
        }),
        { requireReference: true },
      ),
    ApiError,
  );
  assertEquals(error.code, "entitlement_version_required");
});

Deno.test("Reduce and Revoke require explicit confirmation at execution", async () => {
  const error = await assertRejects(
    () =>
      parseManualEntitlementPayload(
        request({
          subjectAccountId: accountId,
          targetType: "Product",
          targetId,
          entitlementId,
          expectedEntitlementVersion: 3,
          operation: "Revoke",
          scheduleMode: "Immediate",
          referenceAtUtc: "2026-08-27T03:00:00.000Z",
          reason:
            "Revoke the selected entitlement after an approved account correction.",
          confirmed: false,
        }),
        { requireReference: true, requireConfirmation: true },
      ),
    ApiError,
  );
  assertEquals(error.code, "confirmation_required");
});

Deno.test("foundation encodes Support request and Sales or Founder approval policy", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827030000_manual_entitlement_operations.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    migration,
    "('support','commerce.entitlement.adjust.request')",
  );
  assertStringIncludes(
    migration,
    "('sales','commerce.entitlement.adjust.approve')",
  );
  assertStringIncludes(migration, "('manual_entitlement_adjustment','sales')");
  assertStringIncludes(
    migration,
    "('manual_entitlement_adjustment','founder')",
  );
  assertStringIncludes(migration, "self_approval_allowed");
});

Deno.test("preview fails closed for FREE baseline and validates Product/Offer feature membership", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827030000_manual_entitlement_operations.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "v_ent.source='FREE'");
  assertStringIncludes(migration, "free_entitlement_not_adjustable");
  assertStringIncludes(migration, "entitlement_target_mismatch");
  assertStringIncludes(
    migration,
    "v_ent.version<>p_expected_entitlement_version",
  );
});

Deno.test("mutation primitives append entitlement events and do not expose table writes to browser roles", async () => {
  const foundation = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827030000_manual_entitlement_operations.sql",
      import.meta.url,
    ),
  );
  const primitives = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827030200_manual_entitlement_mutation_primitives.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(foundation, "force row level security");
  assertStringIncludes(
    foundation,
    "revoke all on commerce.manual_entitlement_adjustments from public,anon,authenticated",
  );
  assertStringIncludes(primitives, "commerce.entitlement_events");
  assertStringIncludes(primitives, "'Adjusted'");
  assert(!primitives.includes("update commerce.subscriptions"));
  assert(!primitives.includes("delete from commerce.subscriptions"));
  assert(!primitives.includes("amount_minor"));
});

Deno.test("server orchestration keeps approval abuse mutation event and audit in one transaction", async () => {
  const service = await Deno.readTextFile(
    new URL("./manual_entitlement_adjustments_service.ts", import.meta.url),
  );
  assertStringIncludes(service, "sql.begin");
  assertStringIncludes(service, "security.evaluate_abuse_rules");
  assertStringIncludes(service, "commerce.manual_adjustment_approval_valid");
  assertStringIncludes(service, "commerce.apply_manual_entitlement_grant");
  assertStringIncludes(service, "commerce.apply_manual_entitlement_change");
  assertStringIncludes(service, "security.record_abuse_event");
  assertStringIncludes(service, "admin.audit_events");
  assert(!service.includes("service_role"));
  assert(!service.includes("supabase.from"));
});

Deno.test("Admin routes provide preview request execute and User 360 consumable history", async () => {
  const routes = await Deno.readTextFile(
    new URL("./manual_entitlement_adjustments_routes.ts", import.meta.url),
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin, "commerce.entitlement.adjust.read")',
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin, "commerce.entitlement.adjust.request")',
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin, "commerce.entitlement.adjust.execute")',
  );
  assertStringIncludes(
    routes,
    "/api/v1/commerce/entitlement-adjustments/preview",
  );
  assertStringIncludes(
    routes,
    "/api/v1/commerce/entitlement-adjustments/requests",
  );
  assertStringIncludes(
    routes,
    "/api/v1/commerce/entitlement-adjustments/execute",
  );
});
