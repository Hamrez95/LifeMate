import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  hashGrowthRewardAdminRequest,
  matchRewardSourceReviewPath,
  parseRewardFulfillmentExecute,
  parseRewardRuleMutation,
} from "./growth_reward_admin.ts";
import { ApiError } from "./validation.ts";

Deno.test("growth reward admin contracts are bounded and deterministic", async () => {
  const rule = await parseRewardRuleMutation(
    new Request("https://admin.test/api/v1/commerce/rewards/rules", {
      method: "POST",
      body: JSON.stringify({
        code: "referral.entitlement",
        triggerKind: "Referral",
        rewardKind: "GiftEntitlement",
        rewardConfig: {
          beneficiarySide: "Referrer",
          targetType: "Offer",
          targetId: "11111111-1111-4111-8111-111111111111",
          durationDays: 30,
        },
        maxIssuesPerAccount: 2,
        status: "Active",
        expectedVersion: 1,
        reason: "Enable the reviewed referral entitlement reward.",
      }),
    }),
  );
  assertEquals(rule.code, "referral.entitlement");
  assertEquals(rule.maxIssuesPerAccount, 2);

  const fulfillment = await parseRewardFulfillmentExecute(
    new Request("https://admin.test/api/v1/commerce/rewards/fulfill", {
      method: "POST",
      body: JSON.stringify({
        rewardEventId: "22222222-2222-4222-8222-222222222222",
        expectedVersion: 1,
        approvalRequestId: "33333333-3333-4333-8333-333333333333",
        approvalExpectedVersion: 2,
        reason: "Fulfill the independently approved reward event.",
      }),
    }),
  );
  assertEquals(fulfillment.approvalExpectedVersion, 2);
  assertEquals(
    matchRewardSourceReviewPath(
      "/api/v1/commerce/rewards/sources/Advocacy/44444444-4444-4444-8444-444444444444/review",
    ),
    {
      sourceKind: "Advocacy",
      sourceId: "44444444-4444-4444-8444-444444444444",
    },
  );
  assertEquals(
    await hashGrowthRewardAdminRequest(fulfillment),
    await hashGrowthRewardAdminRequest({ ...fulfillment }),
  );
});

Deno.test("growth reward admin rejects oversized and malformed mutation input", async () => {
  await assertRejects(
    () =>
      parseRewardRuleMutation(
        new Request("https://admin.test", {
          method: "POST",
          headers: { "content-length": "70000" },
          body: JSON.stringify({}),
        }),
      ),
    ApiError,
  );
});

Deno.test("reward fulfillment consumes canonical approval and reuses guarded entitlement mutation", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827041600_growth_reward_review_fulfillment.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "'growth_reward_fulfillment'");
  assertStringIncludes(migration, "self_approval_allowed=false");
  assertStringIncludes(migration, "admin.consume_approval_request");
  assertStringIncludes(
    migration,
    "commerce.apply_manual_entitlement_grant_guarded",
  );
  assertStringIncludes(migration, "reward_config_snapshot");
  assertStringIncludes(migration, "reward_fulfillment_adapter_unavailable");
  assertStringIncludes(migration, "p_idempotency_key,false,");
  assert(!migration.includes("insert into commerce.entitlements"));
  assert(!migration.includes("update commerce.entitlements"));
});

Deno.test("reward administration remains behind existing Admin RBAC dispatcher", async () => {
  const router = await Deno.readTextFile(
    new URL("./commerce_catalog_routes.ts", import.meta.url),
  );
  const routes = await Deno.readTextFile(
    new URL("./growth_reward_admin_routes.ts", import.meta.url),
  );
  assertStringIncludes(router, "createGrowthRewardAdminRouteHandler");
  assertStringIncludes(router, 'path.startsWith("/api/v1/commerce/rewards/")');
  assertStringIncludes(
    routes,
    'requirePermission(admin, "growth.rewards.write")',
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin, "growth.rewards.read")',
  );
  assertStringIncludes(routes, "requireIdempotencyKey(request)");
});
