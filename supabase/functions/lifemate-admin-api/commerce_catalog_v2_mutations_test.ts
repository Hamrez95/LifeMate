import {
  hashCatalogMutation,
  isCatalogBundleCreatePath,
  isCatalogOfferCreatePath,
  matchCatalogBundlePath,
  matchCatalogOfferPath,
  matchCatalogOfferPricesPath,
  matchCatalogPolicyPath,
  matchCatalogProductPath,
  parseCreateCatalogBundle,
  parseCreateCatalogOffer,
  parseScheduleOfferPrice,
  parseUpdateCatalogBundle,
  parseUpdateCatalogOffer,
  parseUpdateCatalogProduct,
  parseUpsertCatalogPolicy,
} from "./commerce_catalog_v2_mutations.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
async function rejects(fn: () => Promise<unknown>, code: string) {
  try {
    await fn();
  } catch (error) {
    if (
      error && typeof error === "object" && "code" in error &&
      error.code === code
    ) return;
    throw error;
  }
  throw new Error(`Expected ${code}`);
}
const productId = "11111111-1111-4111-8111-111111111111";
const offerId = "22222222-2222-4222-8222-222222222222";
const offerId2 = "33333333-3333-4333-8333-333333333333";
const bundleId = "44444444-4444-4444-8444-444444444444";
function req(body: Record<string, unknown>, method = "PUT") {
  return new Request("https://admin.test/api/v1/commerce/catalog-v2", {
    method,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("catalog v2 route matchers keep resources distinct", () => {
  assertEquals(
    matchCatalogProductPath(
      `/api/v1/commerce/catalog-v2/products/${productId}`,
    ),
    productId,
  );
  assert(
    isCatalogOfferCreatePath("/api/v1/commerce/catalog-v2/offers"),
    "offer collection must match",
  );
  assertEquals(
    matchCatalogOfferPath(`/api/v1/commerce/catalog-v2/offers/${offerId}`),
    offerId,
  );
  assertEquals(
    matchCatalogOfferPricesPath(
      `/api/v1/commerce/catalog-v2/offers/${offerId}/prices`,
    ),
    offerId,
  );
  assertEquals(
    matchCatalogOfferPath(
      `/api/v1/commerce/catalog-v2/offers/${offerId}/prices`,
    ),
    null,
  );
  assertEquals(
    matchCatalogPolicyPath(
      `/api/v1/commerce/catalog-v2/products/${productId}/policies/free.medications.max`,
    ),
    { productId, policyKey: "free.medications.max" },
  );
  assert(
    isCatalogBundleCreatePath("/api/v1/commerce/catalog-v2/bundles"),
    "bundle collection must match",
  );
  assertEquals(
    matchCatalogBundlePath(`/api/v1/commerce/catalog-v2/bundles/${bundleId}`),
    bundleId,
  );
});

Deno.test("product and offer mutations require optimistic versions", async () => {
  const product = await parseUpdateCatalogProduct(
    req({
      name: "LifeMate Core",
      status: "Published",
      expectedVersion: 2,
      reason: "Publish reviewed product catalog revision.",
    }),
  );
  assertEquals(product.expectedVersion, 2);
  const offer = await parseCreateCatalogOffer(
    req({
      productId,
      code: " Yearly-Premium ",
      name: "Yearly Premium",
      durationMonths: 12,
      status: "Hidden",
      giftEligible: true,
      reason: "Create reviewed yearly offer before publication.",
    }, "POST"),
  );
  assertEquals(offer.code, "yearly-premium");
  const updated = await parseUpdateCatalogOffer(
    req({
      name: "Yearly Premium",
      durationMonths: 12,
      status: "Published",
      giftEligible: true,
      expectedVersion: 3,
      reason: "Publish reviewed yearly offer for sale.",
    }),
  );
  assertEquals(updated.expectedVersion, 3);
  await rejects(
    () =>
      parseUpdateCatalogOffer(
        req({
          name: "Yearly Premium",
          durationMonths: 12,
          status: "Published",
          giftEligible: true,
          expectedVersion: 0,
          reason: "Reject stale invalid version from client.",
        }),
      ),
    "catalog_version_invalid",
  );
});

Deno.test("offer price remains bounded append-only metadata", async () => {
  const payload = await parseScheduleOfferPrice(req({
    countryCode: "de",
    currency: "eur",
    storeProvider: "google_play",
    amountMinor: "9999",
    effectiveFromUtc: "2026-09-01T00:00:00+02:00",
    reason: "Schedule reviewed EUR offer price version.",
  }, "POST"));
  assertEquals(payload.countryCode, "DE");
  assertEquals(payload.currency, "EUR");
  assertEquals(payload.amountMinor, "9999");
  await rejects(() =>
    parseScheduleOfferPrice(req({
      countryCode: "DE",
      currency: "EUR",
      storeProvider: "google_play",
      amountMinor: "9223372036854775808",
      effectiveFromUtc: "2026-09-01T00:00:00Z",
      reason: "Reject value beyond PostgreSQL bigint boundary.",
    }, "POST")), "price_amount_invalid");
});

Deno.test("typed catalog policies reject type drift", async () => {
  const policy = await parseUpsertCatalogPolicy(
    req({
      valueType: "integer",
      value: 3,
      status: "Active",
      expectedVersion: 1,
      reason: "Adjust reviewed free medication limit policy.",
    }),
  );
  assertEquals(policy.value, 3);
  await rejects(
    () =>
      parseUpsertCatalogPolicy(
        req({
          valueType: "integer",
          value: "3",
          status: "Active",
          expectedVersion: 1,
          reason: "Reject string value for integer policy type.",
        }),
      ),
    "catalog_policy_value_invalid",
  );
});

Deno.test("bundle composition is unique bounded and versioned", async () => {
  const created = await parseCreateCatalogBundle(
    req({
      code: "complete",
      name: "LifeMate Complete",
      status: "Hidden",
      giftEligible: true,
      offerIds: [offerId, offerId2],
      reason: "Create reviewed ecosystem bundle composition.",
    }, "POST"),
  );
  assertEquals(created.offerIds, [offerId, offerId2]);
  const updated = await parseUpdateCatalogBundle(
    req({
      name: "LifeMate Complete",
      status: "Published",
      giftEligible: true,
      offerIds: [offerId2],
      expectedVersion: 4,
      reason: "Publish reviewed atomic bundle composition revision.",
    }),
  );
  assertEquals(updated.expectedVersion, 4);
  await rejects(
    () =>
      parseCreateCatalogBundle(
        req({
          code: "duplicate",
          name: "Duplicate",
          status: "Hidden",
          giftEligible: true,
          offerIds: [offerId, offerId],
          reason: "Reject duplicate offer composition in a bundle.",
        }, "POST"),
      ),
    "catalog_bundle_items_duplicate",
  );
});

Deno.test("mutation hashes bind operation resource and payload", async () => {
  const payload = { name: "LifeMate Complete", expectedVersion: 2 };
  const a = await hashCatalogMutation(
    "commerce.catalog.bundle.update",
    bundleId,
    payload,
  );
  const b = await hashCatalogMutation(
    "commerce.catalog.bundle.update",
    offerId,
    payload,
  );
  const c = await hashCatalogMutation(
    "commerce.catalog.offer.update",
    bundleId,
    payload,
  );
  assertEquals(a.length, 64);
  assert(a !== b, "resource id must affect hash");
  assert(a !== c, "operation must affect hash");
});
