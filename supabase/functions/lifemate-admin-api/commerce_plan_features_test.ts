import {
  hashConfigureCommercePlanFeatureRequest,
  matchCommercePlanFeaturesPath,
  parseConfigureCommercePlanFeaturePayload,
} from "./commerce_plan_features.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

async function rejects(action: () => Promise<unknown>, code: string) {
  try {
    await action();
  } catch (error) {
    if (
      error && typeof error === "object" && "code" in error &&
      error.code === code
    ) return;
    throw error;
  }
  throw new Error(`Expected ${code}`);
}

const planId = "11111111-1111-4111-8111-111111111111";
const featureId = "22222222-2222-4222-8222-222222222222";
const request = (body: Record<string, unknown>) =>
  new Request("https://admin.test", {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

Deno.test("plan feature route is exactly plan scoped", () => {
  assert(
    matchCommercePlanFeaturesPath(
      `/api/v1/commerce/plans/${planId}/features`,
    ) === planId,
    "feature route must resolve",
  );
  assert(
    matchCommercePlanFeaturesPath(
      `/api/v1/commerce/plans/${planId}/trial-policy`,
    ) === null,
    "trial route must not match",
  );
});

Deno.test("plan feature assignment validates target state and version", async () => {
  const payload = await parseConfigureCommercePlanFeaturePayload(request({
    featureId,
    assigned: true,
    expectedVersion: 0,
    reason: "Enable the reviewed feature for this sellable plan.",
  }));
  assert(
    payload.featureId === featureId && payload.assigned &&
      payload.expectedVersion === 0,
    "valid assignment must parse",
  );

  await rejects(() =>
    parseConfigureCommercePlanFeaturePayload(request({
      featureId,
      assigned: "yes",
      expectedVersion: 0,
      reason: "Reject a non-boolean assignment value safely.",
    })), "plan_feature_assignment_invalid");

  await rejects(() =>
    parseConfigureCommercePlanFeaturePayload(request({
      featureId,
      assigned: false,
      expectedVersion: -1,
      reason: "Reject a stale invalid optimistic version safely.",
    })), "plan_feature_version_invalid");
});

Deno.test("plan feature request hash binds plan feature and version", async () => {
  const payload = await parseConfigureCommercePlanFeaturePayload(request({
    featureId,
    assigned: true,
    expectedVersion: 2,
    reason: "Enable the reviewed feature for this sellable plan.",
  }));
  const original = await hashConfigureCommercePlanFeatureRequest(
    planId,
    payload,
  );
  const changedPlan = await hashConfigureCommercePlanFeatureRequest(
    "33333333-3333-4333-8333-333333333333",
    payload,
  );
  const changedState = await hashConfigureCommercePlanFeatureRequest(planId, {
    ...payload,
    assigned: false,
  });
  assert(
    original.length === 64 && original !== changedPlan &&
      original !== changedState,
    "hash must bind plan and assignment state",
  );
});
