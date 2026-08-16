import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { requirePermission } from "./authorization.ts";
import { json } from "./http.ts";
import { createMarketingAiContentRouteHandler } from "./marketing_ai_content_routes.ts";
import {
  hashCampaignApprovalRequest,
  hashCampaignContentRequest,
  hashCampaignPublishRequest,
  matchMarketingCampaignApprovalPath,
  matchMarketingCampaignContentPath,
  matchMarketingCampaignPublishPath,
  matchMarketingCampaignReadPath,
  parseCampaignApprovalPayload,
  parseCampaignContentPayload,
  parseCampaignPublishPayload,
} from "./marketing_campaign_detail.ts";
import { createMarketingCampaignDetailStore } from "./marketing_campaign_detail_store.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export type MarketingCampaignDetailRouteContext = {
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

export function createMarketingCampaignDetailRouteHandler(databaseUrl: string) {
  const store = createMarketingCampaignDetailStore(databaseUrl);
  const aiContentRouteHandler = createMarketingAiContentRouteHandler(databaseUrl);

  return async function handle(
    context: MarketingCampaignDetailRouteContext,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    const aiContentResponse = await aiContentRouteHandler(context);
    if (aiContentResponse) return aiContentResponse;

    const readId = matchMarketingCampaignReadPath(path);
    if (request.method === "GET" && readId) {
      requirePermission(admin, "marketing.read");
      const detail = await store.get(readId);
      if (!detail) {
        throw new ApiError(
          404,
          "marketing_campaign_not_found",
          "Campaign was not found.",
        );
      }
      return json(detail, 200, origin);
    }

    const contentId = matchMarketingCampaignContentPath(path);
    if (request.method === "PUT" && contentId) {
      requirePermission(admin, "marketing.campaign.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCampaignContentPayload(request);
      const requestHash = await hashCampaignContentRequest(contentId, payload);
      const result = await store.updateContent({
        actorAccountId: accountId,
        campaignId: contentId,
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
            "Campaign content update was not completed.",
          ),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          contentRevision: Number(result.contentRevision),
          approvalState: String(result.approvalState),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    const approvalId = matchMarketingCampaignApprovalPath(path);
    if (request.method === "POST" && approvalId) {
      requirePermission(admin, "marketing.campaign.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCampaignApprovalPayload(request);
      const requestHash = await hashCampaignApprovalRequest(
        approvalId,
        payload,
      );
      const result = await store.setApproval({
        actorAccountId: accountId,
        campaignId: approvalId,
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
          mutationErrorMessage(result, "Campaign approval was not completed."),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          contentRevision: Number(result.contentRevision),
          approvalState: String(result.approvalState),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    const publishId = matchMarketingCampaignPublishPath(path);
    if (request.method === "POST" && publishId) {
      requirePermission(admin, "marketing.social.publish");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCampaignPublishPayload(request);
      const requestHash = await hashCampaignPublishRequest(publishId, payload);
      const result = await store.requestPublish({
        actorAccountId: accountId,
        campaignId: publishId,
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
            "Campaign publish request was not completed.",
          ),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          executionId: String(result.executionId),
          publishStatus: String(result.publishStatus),
          providerConnectivity: "NotVerified",
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    return null;
  };
}
