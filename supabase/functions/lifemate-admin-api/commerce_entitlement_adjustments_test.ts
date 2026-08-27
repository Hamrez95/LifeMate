import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  hashEntitlementAdjustmentPayload,
  parseEntitlementAdjustmentPayload,
} from "./commerce_entitlement_adjustments.ts";
import { ApiError } from "./validation.ts";

function request(body: unknown): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

const accountId = "123e4567-e89b-42d3-a456-426614174000";
const targetId = "223e4567-e89b-42d3-a456-426614174000";

Deno.test("manual entitlement adjustment accepts exact expiry and hashes deterministically", async () => {
  const payload = await parseEntitlementAdjustmentPayload(request({
    accountId,
    targetType: "Offer",
    targetId,
    action: "Extend",
    scheduleMode: "ExactExpiry",
    scheduleAmount: null,
    exactExpiresAtUtc: "2027-01-01T00:00:00Z",
    reason: "Customer entitlement extension approved after support correction.",
    approvalRequestId: null,
    approvalExpectedVersion: null,
  }));
  assertEquals(payload.targetType, "Offer");
  assertEquals(payload.action, "Extend");
  const first = await hashEntitlementAdjustmentPayload(payload);
  const second = await hashEntitlementAdjustmentPayload(payload);
  assertEquals(first, second);
  assert(/^[0-9a-f]{64}$/.test(first));
});

Deno.test("manual adjustment rejects invalid target and oversized month delta", async () => {
  const invalidTarget = await assertRejects(
    () => parseEntitlementAdjustmentPayload(request({
      accountId,
      targetType: "Subscription",
      targetId,
      action: "Grant",
      scheduleMode: "AddMonths",
      scheduleAmount: 1,
      reason: "Invalid target type should fail closed before reaching SQL.",
    })),
    ApiError,
  );
  assertEquals(invalidTarget.code, "target_type_invalid");

  const invalidMonths = await assertRejects(
    () => parseEntitlementAdjustmentPayload(request({
      accountId,
      targetType: "Product",
      targetId,
      action: "Grant",
      scheduleMode: "AddMonths",
      scheduleAmount: 121,
      reason: "Oversized month extension should fail closed before SQL.",
    })),
    ApiError,
  );
  assertEquals(invalidMonths.code, "schedule_amount_invalid");
});

Deno.test("adjustment foundation preserves subscription financial facts and appends events", async () => {
  const migration = await Deno.readTextFile(
    new URL("../../migrations/20260827025000_manual_entitlement_adjustments.sql", import.meta.url),
  );
  assertStringIncludes(migration, "commerce.entitlement_events");
  assertStringIncludes(migration, "ADMIN_GRANT");
  assertStringIncludes(migration, "admin.consume_approval_request");
  assertStringIncludes(migration, "security.evaluate_abuse_rules");
  assertStringIncludes(migration, "security.record_abuse_event");
  assert(!migration.includes("update commerce.subscriptions"));
  assert(!migration.includes("delete from commerce.subscriptions"));
  assert(!migration.includes("amount_minor"));
});

Deno.test("Support requests while Sales or Founder approve and execute", async () => {
  const migration = await Deno.readTextFile(
    new URL("../../migrations/20260827025000_manual_entitlement_adjustments.sql", import.meta.url),
  );
  assertStringIncludes(migration, "('sales','Sales',125,'Active',true)");
  assertStringIncludes(migration, "('support','commerce.entitlement.adjust.request')");
  assertStringIncludes(migration, "('commerce.entitlement.adjustment','sales')");
  assertStringIncludes(migration, "('commerce.entitlement.adjustment','founder')");
  assertStringIncludes(migration, "self_approval_allowed,false");
});

Deno.test("FREE baseline is excluded from the manual adjustment mutation path", async () => {
  const safety = await Deno.readTextFile(
    new URL("../../migrations/20260827025100_manual_entitlement_free_tier_safety.sql", import.meta.url),
  );
  assertStringIncludes(safety, "e.source<>'FREE'");
  assertStringIncludes(safety, "old.source='FREE'");
  assertStringIncludes(safety, "return null");
  assertStringIncludes(safety, "FREE baseline entitlements are never reduced or revoked");
});

Deno.test("canonical admin route provides preview approval template execution and User 360 history source", async () => {
  const routes = await Deno.readTextFile(
    new URL("./commerce_entitlement_adjustments_routes.ts", import.meta.url),
  );
  assertStringIncludes(routes, 'requirePermission(admin, "commerce.entitlement.adjust.request")');
  assertStringIncludes(routes, 'requirePermission(admin, "commerce.entitlement.adjust.execute")');
  assertStringIncludes(routes, 'requirePermission(admin, "commerce.entitlement.adjust.read")');
  assertStringIncludes(routes, 'requestType: "commerce.entitlement.adjustment"');
  assertStringIncludes(routes, "commerce.execute_entitlement_adjustment");
  assert(!routes.includes("service_role"));
  assert(!routes.includes("supabase.from"));
});
