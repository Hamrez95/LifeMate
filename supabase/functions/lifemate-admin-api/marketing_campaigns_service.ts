import type { MarketingCampaignQuery } from "./marketing_campaigns.ts";
import type { MarketingCampaignStore } from "./marketing_campaigns_store.ts";

export type MarketingCampaignListResponse = {
  items: Awaited<ReturnType<MarketingCampaignStore["list"]>>["items"];
  total: number;
  page: number;
  pageSize: number;
  filters: {
    q: string | null;
    product: string | null;
    status: string | null;
    owner: string | null;
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
    page: query.page,
    pageSize: query.pageSize,
    filters: {
      q: query.search,
      product: query.product,
      status: query.status,
      owner: query.ownerAdminAccountId,
    },
    freshness: {
      status: "fresh",
      asOfUtc: result.asOfUtc,
      source: "admin.marketing_campaigns_v1",
    },
  };
}
