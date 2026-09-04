import {
  hashPaymentOperation,
  parseCorrectionExecute,
  parseRefundRequestV2,
  parseRenewalIntent,
} from "./payment_operations.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function assertRejects(
  fn: () => Promise<unknown>,
  expectedCode: string,
) {
  try {
    await fn();
  } catch (error) {
    if (
      error && typeof error === "object" && "code" in error &&
      error.code === expectedCode
    ) return;
    throw error;
  }
  throw new Error(`Expected rejection with ${expectedCode}`);
}

function request(body: Record<string, unknown>) {
  return new Request("https://admin.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

const transactionId = "11111111-1111-4111-8111-111111111111";
const caseId = "22222222-2222-4222-8222-222222222222";
const approvalId = "33333333-3333-4333-8333-333333333333";
const subscriptionId = "44444444-4444-4444-8444-444444444444";

Deno.test("refund parser preserves PostgreSQL bigint precision as text", async () => {
  const parsed = await parseRefundRequestV2(request({
    transactionId,
    amountMinor: "9007199254740993123",
    reason: "Verified partial refund requested by customer support.",
  }));
  assertEquals(parsed.amountMinor, "9007199254740993123");

  await assertRejects(
    () =>
      parseRefundRequestV2(request({
        transactionId,
        amountMinor: "9223372036854775808",
        reason: "Verified partial refund requested by customer support.",
      })),
    "amount_minor_invalid",
  );
});

Deno.test("correction execute parses one request body without clone-after-consume", async () => {
  const parsed = await parseCorrectionExecute(request({
    caseId,
    correctionType: "NormalizedStatusClassification",
    correctedStatus: "Succeeded",
    annotationCode: null,
    reason: "Provider evidence confirms the normalized classification.",
    approvalRequestId: approvalId,
    approvalExpectedVersion: 2,
  }));
  assertEquals(parsed.caseId, caseId);
  assertEquals(parsed.approvalRequestId, approvalId);
  assertEquals(parsed.approvalExpectedVersion, 2);
});

Deno.test("renewal intent requires an explicit boolean", async () => {
  await assertRejects(
    () =>
      parseRenewalIntent(request({
        subscriptionId,
        expectedVersion: 1,
        cancelAtPeriodEnd: "true",
        reasonCode: "user_requested",
      })),
    "cancel_at_period_end_invalid",
  );

  const parsed = await parseRenewalIntent(request({
    subscriptionId,
    expectedVersion: 1,
    cancelAtPeriodEnd: true,
    reasonCode: "user_requested",
  }));
  assertEquals(parsed.cancelAtPeriodEnd, true);
});

Deno.test("payment operation hashing is stable across object key order", async () => {
  const first = await hashPaymentOperation({
    transactionId,
    amountMinor: "250000",
    reason: "Verified partial refund requested by customer support.",
  });
  const second = await hashPaymentOperation({
    reason: "Verified partial refund requested by customer support.",
    amountMinor: "250000",
    transactionId,
  });
  assertEquals(first, second);
  assertEquals(first.length, 64);
});
