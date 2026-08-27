import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  hashEntitlementAdjustmentPayload,
  parseEntitlementAdjustmentPayload,
} from "./entitlement_adjustments.ts";
import { ApiError } from "./validation.ts";

const accountId = "123e4567-e89b-12d3-a456-426614174000";
const targetId = "123e4567-e89b-12d3-a456-426614174001";

function request(body: Record<string, unknown>): Request {
  return new Request("https://example.test/api/v1/commerce/entitlement-adjustments", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function base(overrides: Record<string, unknown> = {}) {
  return {
    accountId,
    targetType: "Offer",
    targetId,
    action: "Extend",
    scheduleMode: "AddDays",
    scheduleAmount: 30,
    exactExpiresAtUtc: null,
    reason: "Support compensation reviewed for this account.",
    confirmed: false,
    approvalRequestId: null,
    approvalExpectedVersion: null,
    ...overrides,
  };
}

Deno.test("manual entitlement payload is bounded and hashes deterministically", async () => {
  const parsed = await parseEntitlementAdjustmentPayload(request(base()));
  assertEquals(parsed.action, "Extend");
  assertEquals(parsed.scheduleAmount, 30);
  assertEquals(
    await hashEntitlementAdjustmentPayload(parsed),
    await hashEntitlementAdjustmentPayload({ ...parsed }),
  );
});

Deno.test("Reduce and Revoke require explicit confirmation", async () => {
  for (const payload of [
    base({
      action: "Reduce",
      scheduleMode: "ExactExpiry",
      scheduleAmount: null,
      exactExpiresAtUtc: "2026-09-30T00:00:00.000Z",
    }),
    base({
      action: "Revoke",
      scheduleMode: "Immediate",
      scheduleAmount: null,
    }),
  ]) {
    const error = await assertRejects(
      () => parseEntitlementAdjustmentPayload(request(payload)),
      ApiError,
    );
    assertEquals(error.code, "entitlement_adjustment_confirmation_required");
  }
});

Deno.test("approval reference is all-or-nothing", async () => {
  const error = await assertRejects(
    () =>
      parseEntitlementAdjustmentPayload(
        request(base({ approvalRequestId: accountId })),
      ),
    ApiError,
  );
  assertEquals(error.code, "approval_reference_invalid");
});

Deno.test("manual entitlement migration preserves FREE tier and financial facts", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827025200_manual_entitlement_adjustment_hardening.sql",
      import.meta.url,
    ),
  );
  const routes = await Deno.readTextFile(
    new URL("./entitlement_adjustments_routes.ts", import.meta.url),
  );

  assertStringIncludes(migration, "e.source<>'FREE'");
  assertStringIncludes(migration, "source,'ADMIN_GRANT'");
  assertStringIncludes(migration, "'Adjusted'");
  assertStringIncludes(migration, "commerce.entitlement.adjust.request");
  assertStringIncludes(migration, "commerce.entitlement.adjust.approve");
  assertStringIncludes(migration, "commerce.entitlement.adjust.execute");
  assertStringIncludes(migration, "admin.consume_approval_request");
  assertStringIncludes(migration, "security.evaluate_abuse_rules");
  assertStringIncludes(migration, "p_confirmed boolean");
  assert(!migration.includes("update commerce.subscriptions"));
  assert(!migration.includes("update commerce.transactions"));
  assert(!migration.includes("update commerce.orders"));
  assert(!routes.includes("service_role"));
  assert(!routes.includes("supabase.from"));
});

Deno.test("Support requests but Sales/Founder execute through explicit permissions", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827025200_manual_entitlement_adjustment_hardening.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    migration,
    "('support','commerce.entitlement.adjust.request')",
  );
  assert(!migration.includes("('support','commerce.entitlement.adjust.execute')"));
  assertStringIncludes(
    migration,
    "('sales','commerce.entitlement.adjust.approve')",
  );
  assertStringIncludes(
    migration,
    "('sales','commerce.entitlement.adjust.execute')",
  );
  assertStringIncludes(
    migration,
    "('founder','commerce.entitlement.adjust.execute')",
  );
  assertStringIncludes(migration, "self_approval_allowed,false");
});

Deno.test("history and mutations remain server-side canonical routes", async () => {
  const routes = await Deno.readTextFile(
    new URL("./entitlement_adjustments_routes.ts", import.meta.url),
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
  assertStringIncludes(routes, "commerce.preview_entitlement_adjustment");
  assertStringIncludes(routes, "commerce.execute_entitlement_adjustment");
  assert(!routes.includes("anon"));
  assert(!routes.includes("authenticated"));
});
