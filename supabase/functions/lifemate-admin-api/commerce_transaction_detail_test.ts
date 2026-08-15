import {
  assertCommerceRefundRequestResult,
  getCommerceRefundCapability,
  hashCommerceRefundRequest,
  matchCommerceRefundRequestPath,
  matchCommerceTransactionDetailPath,
  parseCommerceRefundRequest,
} from "./commerce_transaction_detail.ts";
import { mapCommerceTransactionDetailRow } from "./commerce_transaction_detail_service.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

async function assertRejects(
  fn: () => Promise<unknown>,
  expectedCode: string,
) {
  try {
    await fn();
  } catch (error) {
    if (
      error &&
      typeof error === "object" &&
      "code" in error &&
      error.code === expectedCode
    ) {
      return;
    }
    throw error;
  }
  throw new Error(`Expected rejection with ${expectedCode}`);
}

const transactionId = "11111111-1111-4111-8111-111111111111";

Deno.test("matches transaction detail and refund request routes", () => {
  assertEquals(
    matchCommerceTransactionDetailPath(
      `/api/v1/commerce/transactions/${transactionId}`,
    ),
    transactionId,
  );
  assertEquals(
    matchCommerceRefundRequestPath(
      `/api/v1/commerce/transactions/${transactionId}/actions/refund-request`,
    ),
    transactionId,
  );
  assertEquals(
    matchCommerceTransactionDetailPath(
      `/api/v1/commerce/transactions/${transactionId}/actions/refund-request`,
    ),
    null,
  );
});

Deno.test("refund workflow requires a meaningful reason", async () => {
  const request = new Request("https://admin.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      reason: "  Refund requested after verified duplicate charge.  ",
    }),
  });
  assertEquals(await parseCommerceRefundRequest(request), {
    reason: "Refund requested after verified duplicate charge.",
  });

  await assertRejects(
    () =>
      parseCommerceRefundRequest(
        new Request("https://admin.test", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ reason: "short" }),
        }),
      ),
    "refund_reason_invalid",
  );
});

Deno.test("refund request hash is deterministic and transaction scoped", async () => {
  const first = await hashCommerceRefundRequest(
    transactionId,
    "Refund requested after verified duplicate charge.",
  );
  const replay = await hashCommerceRefundRequest(
    transactionId,
    "Refund requested after verified duplicate charge.",
  );
  const other = await hashCommerceRefundRequest(
    "22222222-2222-4222-8222-222222222222",
    "Refund requested after verified duplicate charge.",
  );
  assertEquals(first, replay);
  assert(first !== other, "hash must bind the request to its transaction");
  assertEquals(first.length, 64);
});

Deno.test("refund capability requires high-risk commerce.refund permission", () => {
  assertEquals(
    getCommerceRefundCapability({
      normalizedStatus: "Succeeded",
      hasActiveWorkflow: false,
      hasPermission: false,
    }),
    {
      available: false,
      permissionRequired: "commerce.refund",
      reason: "MissingPermission",
    },
  );
  assertEquals(
    getCommerceRefundCapability({
      normalizedStatus: "Failed",
      hasActiveWorkflow: false,
      hasPermission: true,
    }).reason,
    "TransactionNotEligible",
  );
  assertEquals(
    getCommerceRefundCapability({
      normalizedStatus: "Succeeded",
      hasActiveWorkflow: true,
      hasPermission: true,
    }).reason,
    "WorkflowAlreadyActive",
  );
  assertEquals(
    getCommerceRefundCapability({
      normalizedStatus: "Succeeded",
      hasActiveWorkflow: false,
      hasPermission: true,
    }).available,
    true,
  );
});

Deno.test("transaction detail mapper is privacy-minimized and bigint-safe", () => {
  const mapped = mapCommerceTransactionDetailRow({
    transaction_id: transactionId,
    order_id: "33333333-3333-4333-8333-333333333333",
    subscription_id: null,
    account_linked: true,
    account_id: "44444444-4444-4444-8444-444444444444",
    product_code: "wellmate",
    product_name: "WellMate",
    provider: "example-provider",
    provider_reference_hash: "secret-hash-that-must-not-map",
    provider_status: "settled",
    normalized_status: "Succeeded",
    amount_minor: 900719925474099312345n,
    currency: "IRR",
    occurred_at_utc: new Date("2026-08-15T09:00:00.000Z"),
    received_at_utc: new Date("2026-08-15T09:00:01.000Z"),
    created_at_utc: new Date("2026-08-15T09:00:01.000Z"),
    updated_at_utc: new Date("2026-08-15T09:00:02.000Z"),
    order_status: "Paid",
    order_amount_minor: 900719925474099312345n,
    order_currency: "IRR",
    order_occurred_at_utc: new Date("2026-08-15T08:59:00.000Z"),
    order_created_at_utc: new Date("2026-08-15T08:59:00.000Z"),
    order_updated_at_utc: new Date("2026-08-15T09:00:02.000Z"),
  });

  assertEquals(mapped.amountMinor, "900719925474099312345");
  assertEquals(mapped.accountLinked, true);
  const serialized = JSON.stringify(mapped);
  assert(!serialized.includes("account_id"), "raw account id must not map");
  assert(!serialized.includes("44444444-4444"), "account id must stay hidden");
  assert(
    !serialized.includes("provider_reference"),
    "provider hash key must stay hidden",
  );
  assert(
    !serialized.includes("secret-hash"),
    "provider hash value must stay hidden",
  );
});

Deno.test("refund result assertion preserves string-backed amount", () => {
  const result = assertCommerceRefundRequestResult({
    httpStatus: 201,
    code: "ok",
    transactionId,
    refundRequestId: "55555555-5555-4555-8555-555555555555",
    status: "PendingReview",
    amountMinor: "900719925474099312345",
    currency: "IRR",
    transactionStatus: "Succeeded",
    replayed: false,
  });
  assertEquals(result.amountMinor, "900719925474099312345");
  assertEquals(result.replayed, false);
});
