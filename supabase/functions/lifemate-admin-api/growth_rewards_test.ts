import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert";
import {
  hashGrowthRewardRequest,
  matchAdvocacyReviewPath,
  parseRewardIssueExecute,
  parseRewardRuleUpsert,
} from "./growth_rewards.ts";
import { ApiError } from "./validation.ts";

Deno.test("growth reward contracts parse bounded rule and reviewed execution payloads", async () => {
  const rule = await parseRewardRuleUpsert(new Request("https://admin.test/api/v1/commerce/rewards/rules", {
    method: "POST",
    body: JSON.stringify({
      code: "referral.welcome",
      triggerKind: "Referral",
      rewardKind: "RaffleEligibility",
      rewardConfig: { pool: "welcome" },
      maxIssuesPerAccount: 1,
      status: "Active",
      reason: "Activate the reviewed welcome referral rule.",
    }),
  }));
  assertEquals(rule.code, "referral.welcome");
  assertEquals(rule.maxIssuesPerAccount, 1);

  const execution = await parseRewardIssueExecute(new Request("https://admin.test/api/v1/commerce/rewards/issue", {
    method: "POST",
    body: JSON.stringify({
      beneficiaryAccountId: "11111111-1111-4111-8111-111111111111",
      sourceKind: "Referral",
      sourceId: "22222222-2222-4222-8222-222222222222",
      rewardRuleId: "33333333-3333-4333-8333-333333333333",
      expectedRuleVersion: 2,
      provenanceHash: "a".repeat(64),
      approvalRequestId: "44444444-4444-4444-8444-444444444444",
      approvalExpectedVersion: 2,
      reason: "Issue the reviewed referral reward after approval.",
    }),
  }));
  assertEquals(execution.approvalExpectedVersion, 2);
  assertEquals(matchAdvocacyReviewPath("/api/v1/commerce/rewards/advocacy/55555555-5555-4555-8555-555555555555/review"), "55555555-5555-4555-8555-555555555555");
  assertEquals(await hashGrowthRewardRequest(execution), await hashGrowthRewardRequest({ ...execution }));
});

Deno.test("growth reward payloads reject malformed provenance", async () => {
  await assertRejects(
    () => parseRewardIssueExecute(new Request("https://admin.test", {
      method: "POST",
      body: JSON.stringify({
        beneficiaryAccountId: "11111111-1111-4111-8111-111111111111",
        sourceKind: "Referral",
        sourceId: "22222222-2222-4222-8222-222222222222",
        rewardRuleId: "33333333-3333-4333-8333-333333333333",
        expectedRuleVersion: 1,
        provenanceHash: "not-a-hash",
        approvalRequestId: "44444444-4444-4444-8444-444444444444",
        approvalExpectedVersion: 2,
        reason: "This reason is sufficiently descriptive.",
      }),
    })),
    ApiError,
  );
});

Deno.test("reward execution reuses canonical approval and guarded entitlement authority", async () => {
  const migration = await Deno.readTextFile(new URL("../../migrations/20260827041300_growth_reward_admin_workflow.sql", import.meta.url));
  assertStringIncludes(migration, "'growth_reward_issue'");
  assertStringIncludes(migration, "self_approval_allowed=false");
  assertStringIncludes(migration, "admin.consume_approval_request");
  assertStringIncludes(migration, "growth.reward_source_is_valid");
  assertStringIncludes(migration, "status in ('Verified','Rewarded')");
  assertStringIncludes(migration, "commerce.apply_manual_entitlement_grant_guarded");
  assertStringIncludes(migration, "v_status:='Pending'");
  assertStringIncludes(migration, "v_fulfillment:='PendingFulfillment'");
  assertStringIncludes(migration, "p_idempotency_key,false,");
  assert(!migration.includes("insert into commerce.entitlements"));
  assert(!migration.includes("update commerce.entitlements"));
});

Deno.test("Commerce router exposes growth rewards only through the authenticated admin dispatcher", async () => {
  const routes = await Deno.readTextFile(new URL("./commerce_catalog_routes.ts", import.meta.url));
  const rewardRoutes = await Deno.readTextFile(new URL("./growth_rewards_routes.ts", import.meta.url));
  assertStringIncludes(routes, "createGrowthRewardAdminRouteHandler");
  assertStringIncludes(routes, 'path.startsWith("/api/v1/commerce/rewards/")');
  assertStringIncludes(rewardRoutes, 'requirePermission(admin, "growth.rewards.write")');
  assertStringIncludes(rewardRoutes, 'requirePermission(admin, "growth.rewards.read")');
  assertStringIncludes(rewardRoutes, 'requireIdempotencyKey(request)');
});
