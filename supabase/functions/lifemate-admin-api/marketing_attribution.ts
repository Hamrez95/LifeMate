import { getAdminSql } from "./database_client.ts";
import { ApiError, requireUuid } from "./validation.ts";

const CODE_PATTERN = /^[a-z0-9][a-z0-9_.:-]{0,63}$/;

export type MarketingAttributionQuery = {
  from: string | null;
  to: string | null;
  product: string | null;
  channel: string | null;
  campaignId: string | null;
};

export type MarketingAttributionMetric = {
  name: "spend" | "revenue" | "conversions" | "cac" | "roas";
  state: "unavailable";
  value: null;
  reason: string;
};

export type MarketingAttributionRow = {
  productCode: string | null;
  channelCode: string | null;
  campaignCount: number;
  activeCampaignCount: number;
  completedCampaignCount: number;
};

function optionalCode(value: string | null, label: string): string | null {
  const normalized = value?.trim().toLowerCase() ?? "";
  if (!normalized) return null;
  if (!CODE_PATTERN.test(normalized)) {
    throw new ApiError(
      400,
      "marketing_attribution_filter_invalid",
      `${label} is invalid.`,
    );
  }
  return normalized;
}

function optionalDate(value: string | null, label: string): string | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
    throw new ApiError(
      400,
      "marketing_attribution_filter_invalid",
      `${label} must use YYYY-MM-DD.`,
    );
  }
  const date = new Date(`${normalized}T00:00:00.000Z`);
  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== normalized
  ) {
    throw new ApiError(
      400,
      "marketing_attribution_filter_invalid",
      `${label} is invalid.`,
    );
  }
  return normalized;
}

export function parseMarketingAttributionQuery(
  url: URL,
): MarketingAttributionQuery {
  const from = optionalDate(url.searchParams.get("from"), "from");
  const to = optionalDate(url.searchParams.get("to"), "to");
  if (from && to && from > to) {
    throw new ApiError(
      400,
      "marketing_attribution_filter_invalid",
      "Attribution date range is invalid.",
    );
  }
  const campaign = url.searchParams.get("campaignId")?.trim() ?? "";
  return {
    from,
    to,
    product: optionalCode(url.searchParams.get("product"), "product"),
    channel: optionalCode(url.searchParams.get("channel"), "channel"),
    campaignId: campaign ? requireUuid(campaign, "campaignId") : null,
  };
}

export const MARKETING_ATTRIBUTION_TAXONOMY = {
  model: "campaign-lifecycle-dimensions-v1",
  attributionState: "not_instrumented" as const,
  dimensions: ["campaign", "product", "channel"] as const,
  supportedFacts: [
    "campaign_count",
    "active_campaign_count",
    "completed_campaign_count",
  ] as const,
  unsupportedFacts: ["spend", "revenue", "conversions", "cac", "roas"] as const,
  note:
    "Campaign lifecycle dimensions are observable, but causal conversion/revenue/spend attribution is not instrumented and must not be inferred.",
};

const unavailableMetrics: MarketingAttributionMetric[] = [
  "spend",
  "revenue",
  "conversions",
  "cac",
  "roas",
].map((name) => ({
  name: name as MarketingAttributionMetric["name"],
  state: "unavailable",
  value: null,
  reason:
    "No canonical spend/revenue/conversion attribution fact is instrumented for campaigns or channels.",
}));

export function createMarketingAttributionStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async read(query: MarketingAttributionQuery) {
      const rows = await sql<
        Array<{
          product_code: string | null;
          channel_code: string | null;
          campaign_count: number | string;
          active_campaign_count: number | string;
          completed_campaign_count: number | string;
        }>
      >`
        select
          c.product_code,
          c.channel_code,
          count(*)::integer as campaign_count,
          count(*) filter (where c.status = 'Active')::integer as active_campaign_count,
          count(*) filter (where c.status = 'Completed')::integer as completed_campaign_count
        from admin.marketing_campaigns_v1 c
        where (${query.product}::text is null or c.product_code = ${query.product})
          and (${query.channel}::text is null or c.channel_code = ${query.channel})
          and (${query.campaignId}::uuid is null or c.campaign_id = ${query.campaignId}::uuid)
          and (${query.from}::date is null or coalesce(c.starts_at_utc, c.created_at_utc) >= (${query.from}::date::timestamp at time zone 'Asia/Tehran'))
          and (${query.to}::date is null or coalesce(c.starts_at_utc, c.created_at_utc) < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran'))
        group by c.product_code, c.channel_code
        order by count(*) desc, c.product_code nulls last, c.channel_code nulls last
        limit 200
      `;

      const items: MarketingAttributionRow[] = rows.map((row) => ({
        productCode: row.product_code,
        channelCode: row.channel_code,
        campaignCount: Number(row.campaign_count),
        activeCampaignCount: Number(row.active_campaign_count),
        completedCampaignCount: Number(row.completed_campaign_count),
      }));

      return {
        taxonomy: MARKETING_ATTRIBUTION_TAXONOMY,
        filters: query,
        items,
        performanceMetrics: unavailableMetrics,
        freshness: {
          status: "partial",
          asOfUtc: new Date().toISOString(),
          source: "admin.marketing_campaigns_v1 lifecycle metadata",
          note:
            "Lifecycle facts are current relational state; spend/revenue/conversion attribution remains not instrumented.",
        },
      };
    },
  };
}
