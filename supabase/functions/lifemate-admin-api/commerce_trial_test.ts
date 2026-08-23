import {
  hashConfigureCommerceTrialRequest,
  matchCommerceTrialPolicyPath,
  parseConfigureCommerceTrialPayload,
} from "./commerce_trial.ts";

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
const request = (body: Record<string, unknown>) =>
  new Request("https://admin.test", {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

Deno.test("trial policy route is plan-scoped", () => {
  assert(
    matchCommerceTrialPolicyPath(
      `/api/v1/commerce/plans/${planId}/trial-policy`,
    ) === planId,
    "plan route must resolve",
  );
  assert(
    matchCommerceTrialPolicyPath(`/api/v1/commerce/plans/${planId}/prices`) ===
      null,
    "price route must not match",
  );
});

Deno.test("trial policy validates lifecycle and optimistic version", async () => {
  const payload = await parseConfigureCommerceTrialPayload(request({
    durationDays: 14,
    eligibilityRule: "NoPriorTrialForProduct",
    status: "Active",
    expectedVersion: 0,
    reason: "Enable the approved founder internal trial policy.",
  }));
  assert(
    payload.durationDays === 14 && payload.expectedVersion === 0,
    "valid policy must parse",
  );
  await rejects(() =>
    parseConfigureCommerceTrialPayload(request({
      durationDays: 0,
      eligibilityRule: "NoPriorTrialForProduct",
      status: "Active",
      expectedVersion: 0,
      reason: "Reject an invalid zero-day trial policy.",
    })), "trial_duration_invalid");
  await rejects(() =>
    parseConfigureCommerceTrialPayload(request({
      durationDays: 14,
      eligibilityRule: "NoPriorTrialForProduct",
      status: "Deleted",
      expectedVersion: 0,
      reason: "Reject unsupported destructive trial lifecycle.",
    })), "trial_status_invalid");
  await rejects(() =>
    parseConfigureCommerceTrialPayload(request({
      durationDays: 14,
      eligibilityRule: "AnyAccount",
      status: "Active",
      expectedVersion: 0,
      reason: "Reject unreviewed trial eligibility semantics.",
    })), "trial_eligibility_invalid");
});

Deno.test("trial policy request hash binds the plan and expected version", async () => {
  const payload = await parseConfigureCommerceTrialPayload(request({
    durationDays: 14,
    eligibilityRule: "NoPriorTrialForProduct",
    status: "Active",
    expectedVersion: 1,
    reason: "Apply the reviewed founder internal trial policy.",
  }));
  const original = await hashConfigureCommerceTrialRequest(planId, payload);
  const changed = await hashConfigureCommerceTrialRequest(
    "22222222-2222-4222-8222-222222222222",
    payload,
  );
  assert(
    original.length === 64 && original !== changed,
    "hash must be plan scoped",
  );
});
