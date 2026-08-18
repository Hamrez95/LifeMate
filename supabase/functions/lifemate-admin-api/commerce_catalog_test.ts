import {
  hashCreateCommercePlanRequest,
  hashScheduleCommercePriceRequest,
  hashUpdateCommercePlanRequest,
  matchCommerceCatalogPlanPath,
  matchCommercePlanPricesPath,
  parseCreateCommercePlanPayload,
  parseScheduleCommercePricePayload,
  parseUpdateCommercePlanPayload,
} from "./commerce_catalog.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(message ?? `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

async function assertRejects(fn: () => Promise<unknown>, expectedCode: string) {
  try {
    await fn();
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === expectedCode) return;
    throw error;
  }
  throw new Error(`Expected rejection with ${expectedCode}`);
}

const planId = "11111111-1111-4111-8111-111111111111";
const productId = "22222222-2222-4222-8222-222222222222";

function request(body: Record<string, unknown>, method = "POST") {
  return new Request("https://admin.test/api/v1/commerce/plans", {
    method,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("catalog route matchers keep plan detail and price collection distinct", () => {
  assertEquals(matchCommerceCatalogPlanPath(`/api/v1/commerce/plans/${planId}`), planId);
  assertEquals(matchCommercePlanPricesPath(`/api/v1/commerce/plans/${planId}/prices`), planId);
  assertEquals(matchCommerceCatalogPlanPath(`/api/v1/commerce/plans/${planId}/prices`), null);
});

Deno.test("plan creation normalizes immutable code and requires meaningful reason", async () => {
  const payload = await parseCreateCommercePlanPayload(request({
    productId,
    code: " Premium-Yearly ",
    name: "Premium Yearly",
    reason: "Approved catalog addition for yearly billing.",
  }));
  assertEquals(payload.code, "premium-yearly");
  assertEquals(payload.productId, productId);

  await assertRejects(
    () => parseCreateCommercePlanPayload(request({
      productId,
      code: "bad code",
      name: "Premium",
      reason: "Approved catalog addition for yearly billing.",
    })),
    "plan_code_invalid",
  );
});

Deno.test("plan update restricts lifecycle to Active or Retired", async () => {
  const payload = await parseUpdateCommercePlanPayload(request({
    name: "Premium Yearly",
    status: "Retired",
    reason: "Retire from new sales while preserving subscribers.",
  }, "PUT"));
  assertEquals(payload.status, "Retired");

  await assertRejects(
    () => parseUpdateCommercePlanPayload(request({
      name: "Premium Yearly",
      status: "Deleted",
      reason: "Attempt unsupported destructive plan lifecycle state.",
    }, "PUT")),
    "plan_status_invalid",
  );
});

Deno.test("price parser uses minor-unit integer strings and canonical dimensions", async () => {
  const payload = await parseScheduleCommercePricePayload(request({
    countryCode: "ir",
    currency: "irr",
    storeProvider: " Google_Play ",
    billingPeriodMonths: 12,
    amountMinor: "9223372036854775807",
    effectiveFromUtc: "2026-09-01T00:00:00+03:30",
    reason: "Schedule reviewed yearly IRR price for the next cycle.",
  }));
  assertEquals(payload.countryCode, "IR");
  assertEquals(payload.currency, "IRR");
  assertEquals(payload.storeProvider, "google_play");
  assertEquals(payload.amountMinor, "9223372036854775807");
  assertEquals(payload.effectiveFromUtc, "2026-08-31T20:30:00.000Z");

  await assertRejects(
    () => parseScheduleCommercePricePayload(request({
      countryCode: "IR",
      currency: "IRR",
      storeProvider: "google_play",
      billingPeriodMonths: 12,
      amountMinor: "9223372036854775808",
      effectiveFromUtc: "2026-09-01T00:00:00Z",
      reason: "Reject amount outside the PostgreSQL bigint boundary.",
    })),
    "price_amount_invalid",
  );
});

Deno.test("catalog mutation hashes are deterministic and resource scoped", async () => {
  const createPayload = await parseCreateCommercePlanPayload(request({
    productId,
    code: "premium",
    name: "Premium",
    reason: "Approved sellable premium plan for the product.",
  }));
  const updatePayload = await parseUpdateCommercePlanPayload(request({
    name: "Premium Plus",
    status: "Active",
    reason: "Rename the plan after approved commercial review.",
  }, "PUT"));
  const pricePayload = await parseScheduleCommercePricePayload(request({
    countryCode: null,
    currency: "USD",
    storeProvider: "manual",
    billingPeriodMonths: 1,
    amountMinor: "999",
    effectiveFromUtc: "2026-09-01T00:00:00Z",
    reason: "Schedule approved monthly global price version.",
  }));

  const createHash = await hashCreateCommercePlanRequest(createPayload);
  assertEquals(createHash.length, 64);
  assertEquals(createHash, await hashCreateCommercePlanRequest(createPayload));

  const updateHash = await hashUpdateCommercePlanRequest(planId, updatePayload);
  const otherUpdateHash = await hashUpdateCommercePlanRequest(
    "33333333-3333-4333-8333-333333333333",
    updatePayload,
  );
  assert(updateHash !== otherUpdateHash, "plan update hash must bind plan id");

  const priceHash = await hashScheduleCommercePriceRequest(planId, pricePayload);
  assert(priceHash !== updateHash, "price and plan mutations need separate operation hashes");
});
