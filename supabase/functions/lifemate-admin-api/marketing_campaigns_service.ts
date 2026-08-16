import type { MarketingCampaignQuery } from "./marketing_campaigns.ts";
import type { MarketingCampaignStore } from "./marketing_campaigns_store.ts";

export type MarketingCampaignListResponse = {
  items: Awaited<ReturnType<MarketingCampaignStore["list"]>>["items"];
  total: number;
  summary: Awaited<ReturnType<MarketingCampaignStore["list"]>>["summary"];
  page: number;
  pageSize: number;
  filters: {
    q: string | null;
    product: string | null;
    channel: string | null;
    status: string | null;
    owner: string | null;
    from: string | null;
    to: string | null;
  };
  freshness: {
    status: "fresh";
    asOfUtc: string;
    source: "admin.marketing_campaigns_v1";
  };
};

export async function listMarketingCampaigns(
  store: MarketingCampaignStore,
  query: MarketingCampaignQuery,
): Promise<MarketingCampaignListResponse> {
  const result = await store.list(query);
  return {
    items: result.items,
    total: result.total,
    summary: result.summary,
    page: query.page,
    pageSize: query.pageSize,
    filters: {
      q: query.search,
      product: query.product,
      channel: query.channel,
      status: query.status,
      owner: query.ownerAdminAccountId,
      from: query.startsFromUtc,
      to: query.startsToUtc,
    },
    freshness: {
      status: "fresh",
      asOfUtc: result.asOfUtc,
      source: "admin.marketing_campaigns_v1",
    },
  };
}
