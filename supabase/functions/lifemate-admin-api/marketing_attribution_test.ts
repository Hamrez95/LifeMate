import {
  MARKETING_ATTRIBUTION_TAXONOMY,
  parseMarketingAttributionQuery,
} from "./marketing_attribution.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("marketing attribution taxonomy never invents commercial facts", () => {
  assert(
    MARKETING_ATTRIBUTION_TAXONOMY.attributionState === "not_instrumented",
    "attribution must remain explicitly not instrumented",
  );
  assert(
    MARKETING_ATTRIBUTION_TAXONOMY.unsupportedFacts.includes("roas") &&
      MARKETING_ATTRIBUTION_TAXONOMY.unsupportedFacts.includes("cac") &&
      MARKETING_ATTRIBUTION_TAXONOMY.unsupportedFacts.includes("revenue") &&
      MARKETING_ATTRIBUTION_TAXONOMY.unsupportedFacts.includes("spend") &&
      MARKETING_ATTRIBUTION_TAXONOMY.unsupportedFacts.includes("conversions"),
    "commercial attribution metrics must stay unsupported until canonical facts exist",
  );
});

Deno.test("marketing attribution parser accepts only bounded canonical filters", () => {
  const campaignId = "11111111-1111-4111-8111-111111111111";
  const query = parseMarketingAttributionQuery(
    new URL(
      `https://example.test/api/v1/marketing/attribution?from=2026-08-01&to=2026-08-26&product=wellmate&channel=instagram&campaignId=${campaignId}`,
    ),
  );
  assert(query.from === "2026-08-01", "from filter must be preserved");
  assert(query.to === "2026-08-26", "to filter must be preserved");
  assert(query.product === "wellmate", "product filter must be normalized");
  assert(query.channel === "instagram", "channel filter must be normalized");
  assert(query.campaignId === campaignId, "campaign id must be validated");
});

Deno.test("marketing attribution parser rejects reversed date ranges", () => {
  let rejected = false;
  try {
    parseMarketingAttributionQuery(
      new URL(
        "https://example.test/api/v1/marketing/attribution?from=2026-08-26&to=2026-08-01",
      ),
    );
  } catch {
    rejected = true;
  }
  assert(rejected, "reversed ranges must be rejected");
});
