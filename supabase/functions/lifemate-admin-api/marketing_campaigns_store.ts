import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  MarketingCampaignItem,
  MarketingCampaignQuery,
  MarketingCampaignStatus,
  MarketingCampaignStatusPayload,
  MarketingCampaignWritePayload,
} from "./marketing_campaigns.ts";
import { ApiError } from "./validation.ts";

export type MarketingCampaignSummary = {
  total: number;
  draft: number;
  ready: number;
  active: number;
  paused: number;
  completed: number;
  cancelled: number;
};

export type MarketingCampaignListResult = {
  items: MarketingCampaignItem[];
  total: number;
  summary: MarketingCampaignSummary;
  asOfUtc: string;
};

type CampaignRow = {
  campaign_id: string;
  name: string;
  objective: string | null;
  product_code: string | null;
  channel_code: string | null;
  status: MarketingCampaignStatus;
  starts_at_utc: Date | string | null;
  ends_at_utc: Date | string | null;
  owner_admin_account_id: string | null;
  created_at_utc: Date | string;
  updated_at_utc: Date | string;
};

type SummaryRow = Record<keyof MarketingCampaignSummary, number | string>;

function iso(value: Date | string | null): string | null {
  if (value == null) return null;
  return value instanceof Date
    ? value.toISOString()
    : new Date(value).toISOString();
}

function mapRow(row: CampaignRow): MarketingCampaignItem {
  return {
    id: row.campaign_id,
    name: row.name,
    objective: row.objective,
    productCode: row.product_code,
    channelCode: row.channel_code,
    status: row.status,
    startsAtUtc: iso(row.starts_at_utc),
    endsAtUtc: iso(row.ends_at_utc),
    ownerAdminAccountId: row.owner_admin_account_id,
    createdAtUtc: iso(row.created_at_utc)!,
    updatedAtUtc: iso(row.updated_at_utc)!,
  };
}

function mapSummary(row: SummaryRow | undefined): MarketingCampaignSummary {
  return {
    total: Number(row?.total ?? 0),
    draft: Number(row?.draft ?? 0),
    ready: Number(row?.ready ?? 0),
    active: Number(row?.active ?? 0),
    paused: Number(row?.paused ?? 0),
    completed: Number(row?.completed ?? 0),
    cancelled: Number(row?.cancelled ?? 0),
  };
}

function assertMutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "marketing_campaign_workflow_unavailable",
      "Campaign workflow result was unavailable.",
    );
  }
  const result = value as Record<string, unknown>;
  if (
    !Number.isInteger(result.httpStatus) ||
    typeof result.code !== "string" ||
    typeof result.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "marketing_campaign_workflow_unavailable",
      "Campaign workflow result was invalid.",
    );
  }
  return result;
}

function campaignFilterSql(sql: AdminSql, query: MarketingCampaignQuery) {
  return sql`
    (${query.search}::text is null
      or c.name ilike '%' || ${query.search} || '%'
      or coalesce(c.objective, '') ilike '%' || ${query.search} || '%')
    and (${query.product}::text is null or c.product_code = ${query.product})
    and (${query.channel}::text is null or c.channel_code = ${query.channel})
    and (${query.status}::text is null or c.status = ${query.status})
    and (${query.ownerAdminAccountId}::uuid is null or c.owner_admin_account_id = ${query.ownerAdminAccountId}::uuid)
    and (${query.startsFromUtc}::timestamptz is null or c.starts_at_utc >= ${query.startsFromUtc}::timestamptz)
    and (${query.startsToUtc}::timestamptz is null or c.starts_at_utc <= ${query.startsToUtc}::timestamptz)
  `;
}

async function listCampaigns(
  sql: AdminSql,
  query: MarketingCampaignQuery,
): Promise<MarketingCampaignItem[]> {
  const filter = campaignFilterSql(sql, query);
  const rows = await sql<CampaignRow[]>`
    select
      c.campaign_id,
      c.name,
      c.objective,
      c.product_code,
      c.channel_code,
      c.status,
      c.starts_at_utc,
      c.ends_at_utc,
      c.owner_admin_account_id,
      c.created_at_utc,
      c.updated_at_utc
    from admin.marketing_campaigns_v1 c
    where ${filter}
    order by c.updated_at_utc desc, c.campaign_id desc
    limit ${query.pageSize}
    offset ${query.offset}
  `;
  return rows.map(mapRow);
}

async function summarizeCampaigns(
  sql: AdminSql,
  query: MarketingCampaignQuery,
): Promise<MarketingCampaignSummary> {
  const filter = campaignFilterSql(sql, query);
  const rows = await sql<SummaryRow[]>`
    select
      count(*)::integer as total,
      count(*) filter (where c.status = 'Draft')::integer as draft,
      count(*) filter (where c.status = 'Ready')::integer as ready,
      count(*) filter (where c.status = 'Active')::integer as active,
      count(*) filter (where c.status = 'Paused')::integer as paused,
      count(*) filter (where c.status = 'Completed')::integer as completed,
      count(*) filter (where c.status = 'Cancelled')::integer as cancelled
    from admin.marketing_campaigns_v1 c
    where ${filter}
  `;
  return mapSummary(rows[0]);
}

export function createMarketingCampaignStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async list(
      query: MarketingCampaignQuery,
    ): Promise<MarketingCampaignListResult> {
      const [items, summary] = await Promise.all([
        listCampaigns(sql, query),
        summarizeCampaigns(sql, query),
      ]);
      return {
        items,
        total: summary.total,
        summary,
        asOfUtc: new Date().toISOString(),
      };
    },

    async create(input: {
      actorAccountId: string;
      payload: MarketingCampaignWritePayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.create_marketing_campaign(
          ${input.actorAccountId}::uuid,
          ${p.name}::varchar,
          ${p.objective}::varchar,
          ${p.productCode}::varchar,
          ${p.channelCode}::varchar,
          ${p.ownerAdminAccountId}::uuid,
          ${p.startsAtUtc}::timestamptz,
          ${p.endsAtUtc}::timestamptz,
          ${p.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },

    async update(input: {
      actorAccountId: string;
      campaignId: string;
      payload: MarketingCampaignWritePayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.update_marketing_campaign(
          ${input.actorAccountId}::uuid,
          ${input.campaignId}::uuid,
          ${p.name}::varchar,
          ${p.objective}::varchar,
          ${p.productCode}::varchar,
          ${p.channelCode}::varchar,
          ${p.ownerAdminAccountId}::uuid,
          ${p.startsAtUtc}::timestamptz,
          ${p.endsAtUtc}::timestamptz,
          ${p.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },

    async setStatus(input: {
      actorAccountId: string;
      campaignId: string;
      payload: MarketingCampaignStatusPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.set_marketing_campaign_status(
          ${input.actorAccountId}::uuid,
          ${input.campaignId}::uuid,
          ${input.payload.status}::varchar,
          ${input.payload.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },
  };
}

export type MarketingCampaignStore = ReturnType<
  typeof createMarketingCampaignStore
>;
