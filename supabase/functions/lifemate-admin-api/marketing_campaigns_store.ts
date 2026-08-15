import type { Sql } from "postgres";

import type {
  MarketingCampaignItem,
  MarketingCampaignQuery,
  MarketingCampaignStatus,
} from "./marketing_campaigns.ts";

export type MarketingCampaignListResult = {
  items: MarketingCampaignItem[];
  total: number;
  asOfUtc: string;
};

type CampaignRow = {
  campaign_id: string;
  name: string;
  objective: string | null;
  product_code: string | null;
  status: MarketingCampaignStatus;
  starts_at_utc: Date | string | null;
  ends_at_utc: Date | string | null;
  owner_admin_account_id: string | null;
  created_at_utc: Date | string;
  updated_at_utc: Date | string;
  total_count: number | string;
};

function iso(value: Date | string | null): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function mapRow(row: CampaignRow): MarketingCampaignItem {
  return {
    id: row.campaign_id,
    name: row.name,
    objective: row.objective,
    productCode: row.product_code,
    status: row.status,
    startsAtUtc: iso(row.starts_at_utc),
    endsAtUtc: iso(row.ends_at_utc),
    ownerAdminAccountId: row.owner_admin_account_id,
    createdAtUtc: iso(row.created_at_utc)!,
    updatedAtUtc: iso(row.updated_at_utc)!,
  };
}

export function createMarketingCampaignStore(sql: Sql) {
  return {
    async list(query: MarketingCampaignQuery): Promise<MarketingCampaignListResult> {
      const rows = await sql<CampaignRow[]>`
        select
          c.campaign_id,
          c.name,
          c.objective,
          c.product_code,
          c.status,
          c.starts_at_utc,
          c.ends_at_utc,
          c.owner_admin_account_id,
          c.created_at_utc,
          c.updated_at_utc,
          count(*) over() as total_count
        from admin.marketing_campaigns_v1 c
        where (${query.search}::text is null or c.name ilike '%' || ${query.search} || '%')
          and (${query.product}::text is null or c.product_code = ${query.product})
          and (${query.status}::text is null or c.status = ${query.status})
          and (${query.ownerAdminAccountId}::uuid is null or c.owner_admin_account_id = ${query.ownerAdminAccountId}::uuid)
        order by c.updated_at_utc desc, c.campaign_id desc
        limit ${query.pageSize}
        offset ${query.offset}
      `;

      return {
        items: rows.map(mapRow),
        total: rows.length === 0 ? 0 : Number(rows[0].total_count),
        asOfUtc: new Date().toISOString(),
      };
    },
  };
}

export type MarketingCampaignStore = ReturnType<typeof createMarketingCampaignStore>;
