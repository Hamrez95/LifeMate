import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { requirePermission } from "./authorization.ts";
import { json } from "./http.ts";
import {
  hashMarketingExecutionActionRequest,
  hashMarketingScheduleRequest,
  matchMarketingCancelExecutionPath,
  matchMarketingRetryExecutionPath,
  matchMarketingSchedulePublishPath,
  parseMarketingContentCalendarQuery,
  parseMarketingExecutionActionPayload,
  parseMarketingSchedulePayload,
} from "./marketing_content_calendar.ts";
import { createMarketingContentCalendarStore } from "./marketing_content_calendar_store.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export type MarketingContentCalendarRouteContext = {
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
      "marketing_calendar_workflow_unavailable",
      "Marketing calendar workflow returned an invalid status.",
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

export function createMarketingContentCalendarRouteHandler(databaseUrl: string) {
  const store = createMarketingContentCalendarStore(databaseUrl);

  return async function handleMarketingContentCalendarRoute(
    context: MarketingContentCalendarRouteContext,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/marketing/content-calendar") {
      requirePermission(admin, "marketing.read");
      const query = parseMarketingContentCalendarQuery(new URL(request.url));
      return json(await store.list(query), 200, origin);
    }

    const campaignId = matchMarketingSchedulePublishPath(path);
    if (request.method === "POST" && campaignId) {
      requirePermission(admin, "marketing.campaign.write");
      requirePermission(admin, "marketing.social.publish");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseMarketingSchedulePayload(request);
      const requestHash = await hashMarketingScheduleRequest(campaignId, payload);
      const result = await store.schedule({
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
          mutationErrorMessage(result, "Campaign scheduling was not completed."),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          executionId: String(result.executionId),
          publishStatus: String(result.publishStatus),
          scheduledForUtc: String(result.scheduledForUtc),
          scheduleTimezone: String(result.scheduleTimezone),
          providerConnectivity: "NotVerified",
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    const cancelExecutionId = matchMarketingCancelExecutionPath(path);
    if (request.method === "POST" && cancelExecutionId) {
      requirePermission(admin, "marketing.social.publish");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseMarketingExecutionActionPayload(request);
      const requestHash = await hashMarketingExecutionActionRequest(
        "cancel",
        cancelExecutionId,
        payload,
      );
      const result = await store.cancel({
        actorAccountId: accountId,
        executionId: cancelExecutionId,
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
          mutationErrorMessage(result, "Scheduled publish cancellation was not completed."),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          executionId: String(result.executionId),
          publishStatus: String(result.publishStatus),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    const retryExecutionId = matchMarketingRetryExecutionPath(path);
    if (request.method === "POST" && retryExecutionId) {
      requirePermission(admin, "marketing.campaign.write");
      requirePermission(admin, "marketing.social.publish");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseMarketingExecutionActionPayload(request);
      const requestHash = await hashMarketingExecutionActionRequest(
        "retry",
        retryExecutionId,
        payload,
      );
      const result = await store.retry({
        actorAccountId: accountId,
        executionId: retryExecutionId,
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
          mutationErrorMessage(result, "Publish retry was not completed."),
        );
      }
      return json(
        {
          campaignId: String(result.campaignId),
          executionId: String(result.executionId),
          retryOfExecutionId: String(result.retryOfExecutionId),
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
