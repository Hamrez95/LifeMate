import { createAdvisorRouteHandler } from "./advisor_routes.ts";
import { createAudienceSegmentRouteHandler } from "./audience_segments_routes.ts";
import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { createCampaignOrchestratorRouteHandler } from "./campaign_orchestrator_routes.ts";
import {
  createCommerceRevenueStore,
  parseCommerceRevenueQuery,
} from "./commerce_revenue.ts";
import { getAdminSql } from "./database_client.ts";
import { createFinanceRouteHandler } from "./finance_routes.ts";
import {
  createGrowthAnalyticsStore,
  parseGrowthAnalyticsQuery,
} from "./growth_analytics.ts";
import { json } from "./http.ts";
import {
  createMarketingAttributionStore,
  parseMarketingAttributionQuery,
} from "./marketing_attribution.ts";
import { createMarketingCampaignDetailRouteHandler } from "./marketing_campaign_detail_routes.ts";
import { createMarketingContentCalendarRouteHandler } from "./marketing_content_calendar_routes.ts";
import {
  hashCreateMarketingCampaignRequest,
  hashMarketingCampaignStatusRequest,
  hashUpdateMarketingCampaignRequest,
  matchMarketingCampaignDetailPath,
  matchMarketingCampaignStatusPath,
  parseMarketingCampaignQuery,
  parseMarketingCampaignStatusPayload,
  parseMarketingCampaignWritePayload,
} from "./marketing_campaigns.ts";
import { listMarketingCampaigns } from "./marketing_campaigns_service.ts";
import { createMarketingCampaignStore } from "./marketing_campaigns_store.ts";
import {
  hashMarketingChannelStatusRequest,
  matchMarketingChannelStatusPath,
  parseMarketingChannelStatusPayload,
} from "./marketing_channels.ts";
import { createMarketingChannelStore } from "./marketing_channels_store.ts";
import { createSecurityRbacRouteHandler } from "./security_rbac_routes.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export type MarketingCampaignRouteContext = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "marketing_workflow_unavailable",
      "Marketing workflow returned an invalid status.",
    );
  }
  return status;
}

function mutationErrorMessage(
  result: Record<string, unknown>,
  fallback: string,
): string {
  return typeof result.message === "string" ? result.message : fallback;
}

export function createMarketingCampaignRouteHandler(databaseUrl: string) {
  const campaignStore = createMarketingCampaignStore(databaseUrl);
  const attributionStore = createMarketingAttributionStore(databaseUrl);
  const revenueStore = createCommerceRevenueStore(databaseUrl);
  const growthStore = createGrowthAnalyticsStore(getAdminSql(databaseUrl));
  const channelStore = createMarketingChannelStore(databaseUrl);
  const detailRouteHandler = createMarketingCampaignDetailRouteHandler(
    databaseUrl,
  );
  const contentCalendarRouteHandler =
    createMarketingContentCalendarRouteHandler(databaseUrl);
  const advisorRouteHandler = createAdvisorRouteHandler(databaseUrl);
  const financeRouteHandler = createFinanceRouteHandler(databaseUrl);
  const securityRbacRouteHandler = createSecurityRbacRouteHandler(databaseUrl);
  const audienceSegmentRouteHandler = createAudienceSegmentRouteHandler(
    databaseUrl,
  );
  const campaignOrchestratorRouteHandler =
    createCampaignOrchestratorRouteHandler(databaseUrl);

  return async function handleMarketingCampaignRoute(
    context: MarketingCampaignRouteContext,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;
    const securityRbacResponse = await securityRbacRouteHandler(context);
    if (securityRbacResponse) return securityRbacResponse;
    const audienceSegmentResponse = await audienceSegmentRouteHandler(context);
    if (audienceSegmentResponse) return audienceSegmentResponse;
    const financeResponse = await financeRouteHandler(context);
    if (financeResponse) return financeResponse;
    const advisorResponse = await advisorRouteHandler(context);
    if (advisorResponse) return advisorResponse;
    const campaignOrchestratorResponse = await campaignOrchestratorRouteHandler(
      context,
    );
    if (campaignOrchestratorResponse) return campaignOrchestratorResponse;
    const contentCalendarResponse = await contentCalendarRouteHandler(context);
    if (contentCalendarResponse) return contentCalendarResponse;
    const detailResponse = await detailRouteHandler(context);
    if (detailResponse) return detailResponse;

    if (request.method === "GET" && path === "/api/v1/analytics/growth") {
      requirePermission(admin, "analytics.read");
      return json(
        await growthStore.read(parseGrowthAnalyticsQuery(new URL(request.url))),
        200,
        origin,
      );
    }
    if (request.method === "GET" && path === "/api/v1/commerce/revenue") {
      requirePermission(admin, "commerce.read");
      return json(
        await revenueStore.read(
          parseCommerceRevenueQuery(new URL(request.url)),
        ),
        200,
        origin,
      );
    }
    if (request.method === "GET" && path === "/api/v1/marketing/channels") {
      requirePermission(admin, "marketing.read");
      return json(
        {
          items: await channelStore.list(),
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
            source: "admin.marketing_channel_connections_v1",
          },
        },
        200,
        origin,
      );
    }
    if (request.method === "GET" && path === "/api/v1/marketing/attribution") {
      requirePermission(admin, "marketing.read");
      return json(
        await attributionStore.read(
          parseMarketingAttributionQuery(new URL(request.url)),
        ),
        200,
        origin,
      );
    }

    const channelProvider = matchMarketingChannelStatusPath(path);
    if (request.method === "POST" && channelProvider) {
      requirePermission(admin, "marketing.social.publish");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseMarketingChannelStatusPayload(request);
      const requestHash = await hashMarketingChannelStatusRequest(
        channelProvider,
        payload,
      );
      const result = await channelStore.setStatus({
        actorAccountId: accountId,
        providerCode: channelProvider,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) {
        throw new ApiError(
          status,
          String(result.code),
          mutationErrorMessage(
            result,
            "Channel operator status change was not completed.",
          ),
        );
      }
      return json(
        {
          providerCode: String(result.providerCode),
          operatorStatus: String(result.operatorStatus),
          setupStatus: String(result.setupStatus),
          replayed: Boolean(result.replayed),
          providerConnectivity: "NotVerified",
        },
        status,
        origin,
      );
    }
    if (request.method === "GET" && path === "/api/v1/marketing/campaigns") {
      requirePermission(admin, "marketing.read");
      return json(
        await listMarketingCampaigns(
          campaignStore,
          parseMarketingCampaignQuery(new URL(request.url)),
        ),
        200,
        origin,
      );
    }
    if (request.method === "POST" && path === "/api/v1/marketing/campaigns") {
      requirePermission(admin, "marketing.campaign.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseMarketingCampaignWritePayload(request);
      const requestHash = await hashCreateMarketingCampaignRequest(payload);
      const result = await campaignStore.create({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) {
        throw new ApiError(
          status,
          String(result.code),
          mutationErrorMessage(result, "Campaign creation was not completed."),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          status: String(result.status),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }
    const statusCampaignId = matchMarketingCampaignStatusPath(path);
    if (request.method === "POST" && statusCampaignId) {
      requirePermission(admin, "marketing.campaign.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseMarketingCampaignStatusPayload(request);
      const requestHash = await hashMarketingCampaignStatusRequest(
        statusCampaignId,
        payload,
      );
      const result = await campaignStore.setStatus({
        actorAccountId: accountId,
        campaignId: statusCampaignId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) {
        throw new ApiError(
          status,
          String(result.code),
          mutationErrorMessage(
            result,
            "Campaign status change was not completed.",
          ),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          previousStatus: String(result.previousStatus),
          status: String(result.status),
          noop: Boolean(result.noop),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }
    const campaignId = matchMarketingCampaignDetailPath(path);
    if (request.method === "PUT" && campaignId) {
      requirePermission(admin, "marketing.campaign.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseMarketingCampaignWritePayload(request);
      const requestHash = await hashUpdateMarketingCampaignRequest(
        campaignId,
        payload,
      );
      const result = await campaignStore.update({
        actorAccountId: accountId,
        campaignId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) {
        throw new ApiError(
          status,
          String(result.code),
          mutationErrorMessage(result, "Campaign update was not completed."),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          previousStatus: String(result.previousStatus),
          status: String(result.status),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }
    return null;
  };
}
