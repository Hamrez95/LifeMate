import {
  parseCommerceRevenueQuery,
  unsupportedRecurringRevenueMetrics,
} from "./commerce_revenue.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("commerce revenue parser preserves explicit bounded dimensions", () => {
  const query = parseCommerceRevenueQuery(
    new URL(
      "https://example.test/api/v1/commerce/revenue?from=2026-08-01&to=2026-08-26&currency=irr&product=wellmate&plan=pro",
    ),
  );

  assert(query.from === "2026-08-01", "from date must be preserved");
  assert(query.to === "2026-08-26", "to date must be preserved");
  assert(query.currency === "IRR", "currency must be normalized explicitly");
  assert(query.product === "wellmate", "product filter must be normalized");
  assert(query.plan === "pro", "plan filter must be normalized");
});

Deno.test("commerce revenue parser rejects invalid ranges and currency", () => {
  let reversed = false;
  try {
    parseCommerceRevenueQuery(
      new URL(
        "https://example.test/api/v1/commerce/revenue?from=2026-08-26&to=2026-08-01",
      ),
    );
  } catch {
    reversed = true;
  }
  assert(reversed, "reversed range must be rejected");

  let currency = false;
  try {
    parseCommerceRevenueQuery(
      new URL("https://example.test/api/v1/commerce/revenue?currency=USDT"),
    );
  } catch {
    currency = true;
  }
  assert(currency, "non-three-letter currency filter must be rejected");
});

Deno.test("recurring revenue metrics never infer values from current prices", () => {
  const metrics = unsupportedRecurringRevenueMetrics("USD");
  assert(
    metrics.length === 5,
    "five unsupported recurring KPIs must be explicit",
  );
  assert(
    metrics.every((metric) => metric.state === "unavailable"),
    "unsupported KPIs must fail closed",
  );
  assert(
    metrics.every((metric) => metric.value === null),
    "unsupported KPIs must never expose invented values",
  );
  assert(
    metrics.find((metric) => metric.name === "mrr")?.reason.includes(
      "price × subscriber count",
    ),
    "MRR boundary must explicitly forbid price-times-subscriber inference",
  );
});
