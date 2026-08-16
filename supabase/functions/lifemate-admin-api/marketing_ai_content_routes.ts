import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { requirePermission } from "./authorization.ts";
import { json } from "./http.ts";
import {
  generateDeterministicMarketingVariants,
  hashMarketingAiContentRequest,
  matchMarketingAiContentGenerationsPath,
  parseMarketingAiContentPayload,
} from "./marketing_ai_content.ts";
import { createMarketingAiContentStore } from "./marketing_ai_content_store.ts";
import { createMarketingCampaignDetailStore } from "./marketing_campaign_detail_store.ts";
import { ApiError, requireIdempotencyKey, requireUuid } from "./validation.ts";

export type MarketingAiContentRouteContext = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

const GENERATION_DETAIL_PATH =
  /^\/api\/v1\/marketing\/campaigns\/([^/]+)\/ai-content\/generations\/([^/]+)$/i;

function matchGenerationDetailPath(
  path: string,
): { campaignId: string; generationId: string } | null {
  const match = GENERATION_DETAIL_PATH.exec(path);
  if (!match) return null;
  return {
    campaignId: requireUuid(match[1], "campaignId"),
    generationId: requireUuid(match[2], "generationId"),
  };
}

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "marketing_ai_content_unavailable",
      "Content Studio returned an invalid workflow status.",
    );
  }
  return status;
}

export function createMarketingAiContentRouteHandler(databaseUrl: string) {
  const store = createMarketingAiContentStore(databaseUrl);
  const campaignStore = createMarketingCampaignDetailStore(databaseUrl);

  return async function handleMarketingAiContentRoute(
    context: MarketingAiContentRouteContext,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, origin } = context;
    const campaignId = matchMarketingAiContentGenerationsPath(path);

    if (campaignId && request.method === "GET") {
      requirePermission(admin, "ai.marketing.use");
      requirePermission(admin, "marketing.read");
      const campaign = await campaignStore.get(campaignId);
      if (!campaign) {
        throw new ApiError(
          404,
          "marketing_campaign_not_found",
          "Campaign was not found.",
        );
      }
      return json(
        {
          items: await store.list(campaignId),
          model: {
            status: "not_configured",
            fallbackUsed: true,
          },
          boundary: {
            publishAllowed: false,
            rawHealthAllowed: false,
            arbitraryPromptAllowed: false,
          },
        },
        200,
        origin,
      );
    }

    if (campaignId && request.method === "POST") {
      requirePermission(admin, "ai.marketing.use");
      requirePermission(admin, "marketing.read");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseMarketingAiContentPayload(request);
      const campaign = await campaignStore.get(campaignId);
      if (!campaign) {
        throw new ApiError(
          404,
          "marketing_campaign_not_found",
          "Campaign was not found.",
        );
      }

      const variants = generateDeterministicMarketingVariants(
        {
          campaignName: campaign.campaign.name,
          objective: campaign.campaign.objective,
          productCode: campaign.campaign.productCode,
          channelCode: campaign.campaign.channelCode,
          brief: campaign.content.brief,
        },
        payload,
      );
      const requestHash = await hashMarketingAiContentRequest(
        campaignId,
        payload,
      );
      const stored = await store.record({
        actorAccountId: accountId,
        campaignId,
        payload,
        generatedVariants: variants,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(stored);
      if (status >= 400) {
        throw new ApiError(
          status,
          String(stored.code),
          status === 409
            ? "This idempotency key was already used for a different Content Studio request."
            : "Content Studio generation was not persisted.",
        );
      }
      const generationId = String(stored.generationId ?? "");
      const generation = generationId
        ? await store.get(campaignId, generationId)
        : null;
      if (!generation) {
        throw new ApiError(
          503,
          "marketing_ai_content_unavailable",
          "Generated content could not be read back safely.",
        );
      }
      return json(
        {
          generation,
          replayed: Boolean(stored.replayed),
          model: {
            status: "not_configured",
            fallbackUsed: true,
            note:
              "No external model is configured. The Studio used the deterministic, bounded draft fallback and requires human selection before campaign content changes.",
          },
          boundary: {
            publishAllowed: false,
            rawHealthAllowed: false,
            arbitraryPromptAllowed: false,
          },
        },
        status,
        origin,
      );
    }

    const detail = matchGenerationDetailPath(path);
    if (detail && request.method === "GET") {
      requirePermission(admin, "ai.marketing.use");
      requirePermission(admin, "marketing.read");
      const generation = await store.get(
        detail.campaignId,
        detail.generationId,
      );
      if (!generation) {
        throw new ApiError(
          404,
          "marketing_ai_content_generation_not_found",
          "Content Studio generation was not found.",
        );
      }
      return json(
        {
          generation,
          boundary: {
            publishAllowed: false,
            rawHealthAllowed: false,
            arbitraryPromptAllowed: false,
          },
        },
        200,
        origin,
      );
    }

    return null;
  };
}
