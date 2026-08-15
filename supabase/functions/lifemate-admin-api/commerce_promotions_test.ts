import {
  hashCreatePromotionRequest,
  hashPromotionStatusRequest,
  hashUpdatePromotionRequest,
  matchCommercePromotionDetailPath,
  matchCommercePromotionStatusPath,
  parseCommercePromotionsQuery,
  parseCreatePromotionPayload,
  parsePromotionStatusPayload,
  parseUpdatePromotionPayload,
} from "./commerce_promotions.ts";

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

const promotionId = "11111111-1111-4111-8111-111111111111";
const productId = "22222222-2222-4222-8222-222222222222";

function promotionRequest(
  body: Record<string, unknown>,
  method = "POST",
): Request {
  return new Request("https://admin.test/api/v1/commerce/promotions", {
    method,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

const percentageBody = {
  productId,
  name: "Launch offer",
  description: "Controlled launch promotion",
  discountType: "Percentage",
  percentageBasisPoints: 1250,
  startsAtUtc: "2026-08-15T09:00:00.000Z",
  endsAtUtc: "2026-09-15T09:00:00.000Z",
  maxRedemptions: 500,
  primaryCode: "WELCOME-125",
  codeMaxRedemptions: 250,
  reason: "Approved launch promotion for the initial cohort.",
};

Deno.test("promotion routes keep detail and status actions distinct", () => {
  assertEquals(
    matchCommercePromotionDetailPath(
      `/api/v1/commerce/promotions/${promotionId}`,
    ),
    promotionId,
  );
  assertEquals(
    matchCommercePromotionStatusPath(
      `/api/v1/commerce/promotions/${promotionId}/actions/status`,
    ),
    promotionId,
  );
  assertEquals(
    matchCommercePromotionDetailPath(
      `/api/v1/commerce/promotions/${promotionId}/actions/status`,
    ),
    null,
  );
});

Deno.test("promotion list search prevents partial code enumeration", () => {
  const query = parseCommercePromotionsQuery(
    new URL(
      "https://admin.test/api/v1/commerce/promotions?q=launch&code=welcome-125&status=Active&page=2&pageSize=20",
    ),
  );
  assertEquals(query.q, "launch");
  assertEquals(query.exactCode, "WELCOME-125");
  assertEquals(query.status, "Active");
  assertEquals(query.page, 2);
  assertEquals(query.pageSize, 20);
});

Deno.test("create parser normalizes codes and enforces bounded limits", async () => {
  const payload = await parseCreatePromotionPayload(
    promotionRequest({ ...percentageBody, primaryCode: " welcome-125 " }),
  );
  assertEquals(payload.primaryCode, "WELCOME-125");
  assertEquals(payload.percentageBasisPoints, 1250);
  assertEquals(payload.fixedAmountMinor, null);
  assertEquals(payload.maxRedemptions, 500);
  assertEquals(payload.codeMaxRedemptions, 250);

  await assertRejects(
    () =>
      parseCreatePromotionPayload(
        promotionRequest({
          ...percentageBody,
          maxRedemptions: 100,
          codeMaxRedemptions: 101,
        }),
      ),
    "promotion_limit_invalid",
  );
});

Deno.test("fixed amount stays string-backed and rejects values beyond PostgreSQL bigint", async () => {
  const accepted = await parseCreatePromotionPayload(
    promotionRequest({
      ...percentageBody,
      discountType: "FixedAmount",
      percentageBasisPoints: undefined,
      fixedAmountMinor: "9223372036854775807",
      currency: "IRR",
    }),
  );
  assertEquals(accepted.fixedAmountMinor, "9223372036854775807");
  assertEquals(accepted.currency, "IRR");

  await assertRejects(
    () =>
      parseCreatePromotionPayload(
        promotionRequest({
          ...percentageBody,
          discountType: "FixedAmount",
          percentageBasisPoints: undefined,
          fixedAmountMinor: "9223372036854775808",
          currency: "IRR",
        }),
      ),
    "promotion_discount_invalid",
  );
});

Deno.test("promotion window and update code state are validated", async () => {
  await assertRejects(
    () =>
      parseCreatePromotionPayload(
        promotionRequest({
          ...percentageBody,
          endsAtUtc: "2026-08-14T09:00:00.000Z",
        }),
      ),
    "promotion_window_invalid",
  );

  const update = await parseUpdatePromotionPayload(
    promotionRequest({ ...percentageBody, codeStatus: "Disabled" }, "PUT"),
  );
  assertEquals(update.codeStatus, "Disabled");

  await assertRejects(
    () =>
      parseUpdatePromotionPayload(
        promotionRequest({ ...percentageBody, codeStatus: "Unknown" }, "PUT"),
      ),
    "discount_code_status_invalid",
  );
});

Deno.test("status mutation requires lifecycle state and meaningful reason", async () => {
  assertEquals(
    await parsePromotionStatusPayload(
      promotionRequest(
        {
          status: "Paused",
          reason: "Paused while finance reviews the promotion terms.",
        },
        "POST",
      ),
    ),
    {
      status: "Paused",
      reason: "Paused while finance reviews the promotion terms.",
    },
  );

  await assertRejects(
    () =>
      parsePromotionStatusPayload(
        promotionRequest(
          {
            status: "Expired",
            reason: "Attempt to force lifecycle state directly.",
          },
          "POST",
        ),
      ),
    "promotion_status_invalid",
  );
});

Deno.test("promotion mutation hashes are deterministic and resource scoped", async () => {
  const createPayload = await parseCreatePromotionPayload(
    promotionRequest(percentageBody),
  );
  const updatePayload = await parseUpdatePromotionPayload(
    promotionRequest({ ...percentageBody, codeStatus: "Active" }, "PUT"),
  );
  const statusPayload = await parsePromotionStatusPayload(
    promotionRequest(
      {
        status: "Active",
        reason: "Activate after commercial review is complete.",
      },
      "POST",
    ),
  );

  const createHash = await hashCreatePromotionRequest(createPayload);
  assertEquals(createHash, await hashCreatePromotionRequest(createPayload));
  assertEquals(createHash.length, 64);

  const updateHash = await hashUpdatePromotionRequest(
    promotionId,
    updatePayload,
  );
  const otherUpdateHash = await hashUpdatePromotionRequest(
    "33333333-3333-4333-8333-333333333333",
    updatePayload,
  );
  assert(updateHash !== otherUpdateHash, "update hash must bind promotion id");

  const statusHash = await hashPromotionStatusRequest(
    promotionId,
    statusPayload,
  );
  assert(statusHash !== updateHash, "action hashes must be operation scoped");
});
