import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  CampaignApprovalPayload,
  CampaignContentPayload,
  CampaignPublishPayload,
  CampaignPublishStatus,
} from "./marketing_campaign_detail.ts";
import type { MarketingCampaignStatus } from "./marketing_campaigns.ts";
import { ApiError } from "./validation.ts";

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

type ContentRow = {
  brief: string | null;
  audience_summary: string | null;
  publish_text: string | null;
  asset_refs: unknown;
  content_revision: number | string;
  approval_state: "Pending" | "Approved" | "Revoked";
  approved_revision: number | string | null;
  approved_by_admin_account_id: string | null;
  approved_at_utc: Date | string | null;
  updated_at_utc: Date | string;
};

type FunnelRow = {
  source: string;
  impressions: number | string | null;
  clicks: number | string | null;
  landing_views: number | string | null;
  conversions: number | string | null;
  captured_at_utc: Date | string;
};

type PublishRow = {
  id: string;
  provider_code: string;
  content_revision: number | string;
  status: CampaignPublishStatus;
  requested_by_admin_account_id: string;
  requested_at_utc: Date | string;
  started_at_utc: Date | string | null;
  completed_at_utc: Date | string | null;
  provider_post_ref: string | null;
  failure_code: string | null;
};

type ChannelRow = {
  provider_code: string;
  display_name: string;
  operator_status: "Enabled" | "Disabled";
  setup_status: "SetupRequired" | "CredentialAvailable" | "Disabled";
  credential_available: boolean;
  updated_at_utc: Date | string;
};

function iso(value: Date | string | null): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function mutation(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(503, "marketing_campaign_workflow_unavailable", "Campaign workflow result was unavailable.");
  }
  const result = value as Record<string, unknown>;
  if (!Number.isInteger(result.httpStatus) || typeof result.code !== "string" || typeof result.replayed !== "boolean") {
    throw new ApiError(503, "marketing_campaign_workflow_unavailable", "Campaign workflow result was invalid.");
  }
  return result;
}

export function createMarketingCampaignDetailStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async get(campaignId: string) {
      const campaigns = await sql<CampaignRow[]>`
        select campaign_id,name,objective,product_code,channel_code,status,starts_at_utc,ends_at_utc,
               owner_admin_account_id,created_at_utc,updated_at_utc
        from admin.marketing_campaigns_v1 where campaign_id=${campaignId}::uuid limit 1
      `;
      const campaign = campaigns[0];
      if (!campaign) return null;

      const [contents, funnels, history, channels] = await Promise.all([
        sql<ContentRow[]>`select brief,audience_summary,publish_text,asset_refs,content_revision,approval_state,
          approved_revision,approved_by_admin_account_id,approved_at_utc,updated_at_utc
          from marketing.campaign_content where campaign_id=${campaignId}::uuid limit 1`,
        sql<FunnelRow[]>`select source,impressions,clicks,landing_views,conversions,captured_at_utc
          from marketing.campaign_funnel_snapshots where campaign_id=${campaignId}::uuid
          order by captured_at_utc desc,id desc limit 1`,
        sql<PublishRow[]>`select id,provider_code,content_revision,status,requested_by_admin_account_id,requested_at_utc,
          started_at_utc,completed_at_utc,provider_post_ref,failure_code
          from marketing.campaign_publish_executions where campaign_id=${campaignId}::uuid
          order by requested_at_utc desc,id desc limit 50`,
        campaign.channel_code
          ? sql<ChannelRow[]>`select provider_code,display_name,operator_status,setup_status,credential_available,updated_at_utc
              from admin.marketing_channel_connections_v1 where provider_code=${campaign.channel_code} limit 1`
          : Promise.resolve([] as ChannelRow[]),
      ]);
      const content = contents[0];
      const funnel = funnels[0];
      const channel = channels[0];
      const assetRefs = Array.isArray(content?.asset_refs)
        ? content.asset_refs.filter((value): value is string => typeof value === "string")
        : [];

      return {
        campaign: {
          id: campaign.campaign_id,
          name: campaign.name,
          objective: campaign.objective,
          productCode: campaign.product_code,
          channelCode: campaign.channel_code,
          status: campaign.status,
          startsAtUtc: iso(campaign.starts_at_utc),
          endsAtUtc: iso(campaign.ends_at_utc),
          ownerAdminAccountId: campaign.owner_admin_account_id,
          createdAtUtc: iso(campaign.created_at_utc)!,
          updatedAtUtc: iso(campaign.updated_at_utc)!,
        },
        content: content
          ? {
              brief: content.brief,
              audienceSummary: content.audience_summary,
              publishText: content.publish_text,
              assetRefs,
              contentRevision: Number(content.content_revision),
              approvalState: content.approval_state,
              approvedRevision: content.approved_revision == null ? null : Number(content.approved_revision),
              approvedByAdminAccountId: content.approved_by_admin_account_id,
              approvedAtUtc: iso(content.approved_at_utc),
              updatedAtUtc: iso(content.updated_at_utc)!,
            }
          : {
              brief: null,
              audienceSummary: null,
              publishText: null,
              assetRefs: [],
              contentRevision: 0,
              approvalState: "Pending" as const,
              approvedRevision: null,
              approvedByAdminAccountId: null,
              approvedAtUtc: null,
              updatedAtUtc: null,
            },
        funnel: funnel
          ? {
              availability: "Available" as const,
              source: funnel.source,
              asOfUtc: iso(funnel.captured_at_utc),
              metrics: {
                impressions: funnel.impressions == null ? null : Number(funnel.impressions),
                clicks: funnel.clicks == null ? null : Number(funnel.clicks),
                landingViews: funnel.landing_views == null ? null : Number(funnel.landing_views),
                conversions: funnel.conversions == null ? null : Number(funnel.conversions),
              },
            }
          : {
              availability: "Unavailable" as const,
              source: "not_instrumented",
              asOfUtc: null,
              metrics: { impressions: null, clicks: null, landingViews: null, conversions: null },
            },
        channel: channel
          ? {
              providerCode: channel.provider_code,
              displayName: channel.display_name,
              operatorStatus: channel.operator_status,
              setupStatus: channel.setup_status,
              credentialAvailable: channel.credential_available,
              providerConnectivity: "NotVerified" as const,
              updatedAtUtc: iso(channel.updated_at_utc)!,
            }
          : null,
        publishHistory: history.map((row) => ({
          id: row.id,
          providerCode: row.provider_code,
          contentRevision: Number(row.content_revision),
          status: row.status,
          requestedByAdminAccountId: row.requested_by_admin_account_id,
          requestedAtUtc: iso(row.requested_at_utc)!,
          startedAtUtc: iso(row.started_at_utc),
          completedAtUtc: iso(row.completed_at_utc),
          providerPostRef: row.provider_post_ref,
          failureCode: row.failure_code,
        })),
        freshness: { status: "fresh" as const, asOfUtc: new Date().toISOString(), source: "marketing campaign aggregate" },
      };
    },

    async updateContent(input: { actorAccountId: string; campaignId: string; payload: CampaignContentPayload; correlationId: string; idempotencyKey: string; requestHash: string }) {
      const p = input.payload;
      const rows = await sql`select admin.update_marketing_campaign_content(
        ${input.actorAccountId}::uuid,${input.campaignId}::uuid,${p.brief}::varchar,${p.audienceSummary}::varchar,
        ${p.publishText}::varchar,${JSON.stringify(p.assetRefs)}::jsonb,${p.reason}::varchar,${input.correlationId}::uuid,
        ${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return mutation(rows[0]?.result);
    },

    async setApproval(input: { actorAccountId: string; campaignId: string; payload: CampaignApprovalPayload; correlationId: string; idempotencyKey: string; requestHash: string }) {
      const rows = await sql`select admin.set_marketing_campaign_approval(
        ${input.actorAccountId}::uuid,${input.campaignId}::uuid,${input.payload.approved},${input.payload.reason}::varchar,
        ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return mutation(rows[0]?.result);
    },

    async requestPublish(input: { actorAccountId: string; campaignId: string; payload: CampaignPublishPayload; correlationId: string; idempotencyKey: string; requestHash: string }) {
      const rows = await sql`select admin.request_marketing_campaign_publish(
        ${input.actorAccountId}::uuid,${input.campaignId}::uuid,${input.payload.reason}::varchar,${input.correlationId}::uuid,
        ${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result`;
      return mutation(rows[0]?.result);
    },
  };
}

export type MarketingCampaignDetailStore = ReturnType<typeof createMarketingCampaignDetailStore>;
