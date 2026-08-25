import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { getAnalyticsCatalog } from "./analytics_catalog.ts";
import { createAnalyticsKpiStore } from "./analytics_kpi_service.ts";
import { parseAnalyticsKpiQuery } from "./analytics_kpis.ts";
import { parseAuditQuery } from "./audit.ts";
import { authenticate, requireAal2 } from "./auth.ts";
import { requirePermission } from "./authorization.ts";
import { parseCommerceOverviewQuery } from "./commerce.ts";
import { createCommerceCatalogRouteHandler } from "./commerce_catalog_routes.ts";
import { createCommerceTrialRouteHandler } from "./commerce_trial_routes.ts";
import {
  matchCommerceEntitlementDetailPath,
  matchCommercePlanDetailPath,
  parseCommerceDetailQuery,
} from "./commerce_detail.ts";
import { createCommerceDetailStore } from "./commerce_detail_service.ts";
import {
  hashCreatePromotionRequest,
  hashPromotionStatusRequest,
  hashUpdatePromotionRequest,
  matchCommercePromotionDetailPath,
  matchCommercePromotionStatusPath,
  parseCommercePromotionsQuery,
  parseCreatePromotionPayload,
  parsePromotionStatusPayload,
  parseUpdatePromotionPayload,
} from "./commerce_promotions.ts";
import { createCommercePromotionsStore } from "./commerce_promotions_service.ts";
import { createCommerceOverviewStore } from "./commerce_service.ts";
import {
  getCommerceRefundCapability,
  hashCommerceRefundRequest,
  matchCommerceRefundRequestPath,
  matchCommerceTransactionDetailPath,
  parseCommerceRefundRequest,
} from "./commerce_transaction_detail.ts";
import { createCommerceTransactionDetailStore } from "./commerce_transaction_detail_service.ts";
import { parseCommerceTransactionsQuery } from "./commerce_transactions.ts";
import { createCommerceTransactionsStore } from "./commerce_transactions_service.ts";
import {
  authorizedSearchDomains,
  parseGlobalSearchQuery,
  safeSearchLogFields,
} from "./global_search.ts";
import { createGlobalSearchStore } from "./global_search_service.ts";
import {
  authorizedNotificationSources,
  hashNotificationReadStateRequest,
  notificationPermission,
  parseNotificationCountQuery,
  parseNotificationQuery,
  parseNotificationReadStateRequest,
} from "./notifications.ts";
import { createNotificationCenterStore } from "./notifications_service.ts";
import { isPostgresUnavailable } from "./database_client.ts";
import { parseUserDirectoryQuery } from "./directory.ts";
import {
  assertAllowedOrigin,
  json,
  preflight,
  problem,
  responseHeaders,
  safeError,
} from "./http.ts";
import { createMarketingCampaignRouteHandler } from "./marketing_campaigns_routes.ts";
import { parseRelationshipLedgerQuery } from "./relationship_ledger.ts";
import { createRelationshipLedgerStore } from "./relationship_ledger_service.ts";
import { createRelationshipOverviewStore } from "./relationship_overview_service.ts";
import { parseRelationshipOverviewQuery } from "./relationships.ts";
import { loadRuntimeConfig } from "./runtime_config.ts";
import { createAdminStore } from "./store.ts";
import { parseSupportQueueQuery } from "./support.ts";
import {
  hashSupportTicketActionRequest,
  matchSupportTicketActionPath,
  matchSupportTicketDetailPath,
  matchSupportTicketEventsPath,
  parseSupportTicketActionPayload,
  parseSupportTicketEventsQuery,
} from "./support_detail.ts";
import { createSupportTicketDetailStore } from "./support_detail_store.ts";
import { createSupportQueueStore } from "./support_service.ts";
import {
  hashStaffActionRequest,
  matchStaffActionPath,
  parseStaffActionRequest,
} from "./staff_actions.ts";
import { createStaffActionStore } from "./staff_actions_service.ts";
import { createUserAccountActionStore } from "./user_action_store.ts";
import {
  hashUserAccountActionRequest,
  matchUserAccountActionPath,
  parseUserAccountActionRequest,
} from "./user_actions.ts";
import {
  matchUserActivityPath,
  matchUserDetailPath,
  parseUserActivityQuery,
  userDetailAccountData,
} from "./user_detail.ts";
import { getUserDetailSectionPermissions } from "./user_detail_permissions.ts";
import { createUserDetailStore } from "./user_detail_store.ts";
import {
  ApiError,
  normalizePath,
  requireIdempotencyKey,
} from "./validation.ts";

const config = await loadRuntimeConfig();
const store = createAdminStore(config.databaseUrl);
const userDetailStore = createUserDetailStore(config.databaseUrl);
const globalSearchStore = createGlobalSearchStore(config.databaseUrl);
const notificationCenterStore = createNotificationCenterStore(
  config.databaseUrl,
);
const userAccountActionStore = createUserAccountActionStore(config.databaseUrl);
const analyticsKpiStore = createAnalyticsKpiStore(config.databaseUrl);
const commerceOverviewStore = createCommerceOverviewStore(config.databaseUrl);
const commerceDetailStore = createCommerceDetailStore(config.databaseUrl);
const commerceCatalogRouteHandler = createCommerceCatalogRouteHandler(
  config.databaseUrl,
);
const commerceTrialRouteHandler = createCommerceTrialRouteHandler(
  config.databaseUrl,
);
const commercePromotionsStore = createCommercePromotionsStore(
  config.databaseUrl,
);
const commerceTransactionsStore = createCommerceTransactionsStore(
  config.databaseUrl,
);
const commerceTransactionDetailStore = createCommerceTransactionDetailStore(
  config.databaseUrl,
);
const relationshipOverviewStore = createRelationshipOverviewStore(
  config.databaseUrl,
);
const relationshipLedgerStore = createRelationshipLedgerStore(
  config.databaseUrl,
);
const supportQueueStore = createSupportQueueStore(config.databaseUrl);
const supportTicketDetailStore = createSupportTicketDetailStore(
  config.databaseUrl,
);
const marketingCampaignRouteHandler = createMarketingCampaignRouteHandler(
  config.databaseUrl,
);
const staffActionStore = createStaffActionStore(config.databaseUrl);

async function optionalSection<T>(
  allowed: boolean,
  load: () => Promise<T>,
  isEmpty: (value: T) => boolean,
  correlationId: string,
  section: string,
) {
  if (!allowed) return { state: "forbidden" as const };

  try {
    const data = await load();
    return isEmpty(data)
      ? { state: "empty" as const }
      : { state: "ready" as const, data };
  } catch (error) {
    console.warn("LifeMate Admin optional User 360 section unavailable", {
      correlationId,
      section,
      ...safeError(error),
    });
    return { state: "unavailable" as const };
  }
}

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "promotion_workflow_unavailable",
      "Promotion workflow returned an invalid status.",
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

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();
  const path = normalizePath(new URL(request.url).pathname);
  let origin: string | null = null;

  try {
    origin = assertAllowedOrigin(request, config.allowedOrigins);
    if (request.method === "OPTIONS") {
      if (!origin) {
        throw new ApiError(
          403,
          "origin_denied",
          "Request origin is not allowed.",
        );
      }
      return preflight(origin);
    }

    if (request.method === "GET" && path === "/health") {
      await store.health();
      return json(
        {
          status: "ok",
          service: "lifemate-admin-api",
          database: "ready",
          version: config.releaseVersion,
        },
        200,
        origin,
      );
    }

    const principal = await authenticate(
      request,
      config.supabaseUrl,
      config.publishableKey,
    );
    requireAal2(principal);
    const accountId = await store.resolveAccountId(principal.providerSubject);

    if (request.method === "POST" && path === "/api/v1/bootstrap") {
      if (
        !config.bootstrapAuthSubject ||
        principal.providerSubject !== config.bootstrapAuthSubject
      ) {
        throw new ApiError(
          403,
          "admin_bootstrap_denied",
          "Admin bootstrap is not permitted.",
        );
      }
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.bootstrapFounder(
        accountId,
        correlationId,
        idempotencyKey,
      );
      return json(
        {
          bootstrapped: true,
          created: result.created,
          admin: await store.getSnapshot(accountId),
        },
        result.created ? 201 : 200,
        origin,
      );
    }

    const admin = await store.getSnapshot(accountId);

    if (request.method === "GET" && path === "/api/v1/me") {
      return json({ admin }, 200, origin);
    }

    const staffActionRoute = matchStaffActionPath(path);
    if (request.method === "POST" && staffActionRoute) {
      requirePermission(admin, "security.staff.manage");
      const idempotencyKey = requireIdempotencyKey(request);
      const staffRequest = await parseStaffActionRequest(
        request,
        staffActionRoute,
      );
      const requestHash = await hashStaffActionRequest(
        staffActionRoute,
        staffRequest,
      );
      const result = await staffActionStore.mutate({
        actorAccountId: accountId,
        route: staffActionRoute,
        request: staffRequest,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) {
        throw new ApiError(
          status,
          String(result.code),
          mutationErrorMessage(result, "Staff mutation was not completed."),
        );
      }
      return json(
        {
          accountId: String(result.accountId),
          roleCode: typeof result.roleCode === "string"
            ? result.roleCode
            : null,
          status: typeof result.status === "string" ? result.status : null,
          previousStatus: typeof result.previousStatus === "string"
            ? result.previousStatus
            : null,
          action: typeof result.action === "string"
            ? result.action
            : staffActionRoute.action,
          noop: Boolean(result.noop),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    const marketingCampaignResponse = await marketingCampaignRouteHandler({
      request,
      path,
      accountId,
      admin,
      correlationId,
      origin,
    });
    if (marketingCampaignResponse) return marketingCampaignResponse;

    const commerceCatalogResponse = await commerceCatalogRouteHandler({
      request,
      path,
      accountId,
      admin,
      correlationId,
      origin,
    });
    if (commerceCatalogResponse) return commerceCatalogResponse;

    const commerceTrialResponse = await commerceTrialRouteHandler({
      request,
      path,
      accountId,
      admin,
      correlationId,
      origin,
    });
    if (commerceTrialResponse) return commerceTrialResponse;

    if (request.method === "GET" && path === "/api/v1/search") {
      const query = parseGlobalSearchQuery(new URL(request.url));
      const authorizedDomains = authorizedSearchDomains(
        query.domains,
        admin.permissions,
      );
      if (authorizedDomains.length === 0) {
        throw new ApiError(
          403,
          "search_forbidden",
          "No requested search domain is authorized for this admin.",
        );
      }

      const rateLimit = await globalSearchStore.consumeRateLimit(accountId);
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({
            type: "https://lifemate.app/problems/search_rate_limited",
            title: "Search request rate limit exceeded.",
            status: 429,
            code: "search_rate_limited",
            correlationId,
          }),
          {
            status: 429,
            headers: {
              ...responseHeaders(origin),
              "retry-after": String(rateLimit.retryAfterSeconds),
            },
          },
        );
      }

      console.info("LifeMate Admin global search", {
        correlationId,
        ...safeSearchLogFields(query, authorizedDomains),
        remaining: rateLimit.remaining,
      });
      const groups = await globalSearchStore.search(query, authorizedDomains);
      return json(
        {
          groups,
          page: query.page,
          pageSize: query.pageSize,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/notifications") {
      const query = parseNotificationQuery(new URL(request.url));
      const authorizedSources = authorizedNotificationSources(
        query.sources,
        admin.permissions,
      );
      if (authorizedSources.length === 0) {
        throw new ApiError(
          403,
          "notifications_forbidden",
          "No requested notification source is authorized for this admin.",
        );
      }
      return json(
        await notificationCenterStore.list(
          accountId,
          query,
          authorizedSources,
          correlationId,
        ),
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/notifications/count") {
      const query = parseNotificationCountQuery(new URL(request.url));
      const authorizedSources = authorizedNotificationSources(
        query.sources,
        admin.permissions,
      );
      if (authorizedSources.length === 0) {
        throw new ApiError(
          403,
          "notifications_forbidden",
          "No requested notification source is authorized for this admin.",
        );
      }
      return json(
        await notificationCenterStore.count(
          accountId,
          authorizedSources,
          correlationId,
        ),
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/notifications/actions/read-state"
    ) {
      const payload = await parseNotificationReadStateRequest(request);
      requirePermission(admin, notificationPermission[payload.source]);
      if (
        !(await notificationCenterStore.hasActiveAlert(
          payload.source,
          payload.alertKey,
        ))
      ) {
        throw new ApiError(
          404,
          "notification_not_found",
          "Notification was not found.",
        );
      }
      const idempotencyKey = requireIdempotencyKey(request);
      const requestHash = await hashNotificationReadStateRequest(payload);
      const result = await notificationCenterStore.setReadState(
        accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      );
      return json(result, result.httpStatus, origin);
    }

    if (request.method === "GET" && path === "/api/v1/analytics/catalog") {
      requirePermission(admin, "analytics.read");
      return json(getAnalyticsCatalog(), 200, origin);
    }

    if (request.method === "GET" && path === "/api/v1/analytics/kpis") {
      requirePermission(admin, "analytics.read");
      const query = parseAnalyticsKpiQuery(new URL(request.url));
      return json(
        {
          query,
          values: await analyticsKpiStore.getValues(query),
          generatedAtUtc: new Date().toISOString(),
        },
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/commerce/overview") {
      requirePermission(admin, "commerce.read");
      const query = parseCommerceOverviewQuery(new URL(request.url));
      const result = await commerceOverviewStore.getOverview(query);
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          filters: {
            product: query.product,
            status: query.status,
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/commerce/promotions") {
      requirePermission(admin, "commerce.read");
      const query = parseCommercePromotionsQuery(new URL(request.url));
      const result = await commercePromotionsStore.list(query);
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          filters: {
            product: query.product,
            status: query.status,
            q: query.q,
            code: query.exactCode,
          },
          source: {
            kind: "canonical",
            label: "LifeMate Commerce promotion ledger",
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (request.method === "POST" && path === "/api/v1/commerce/promotions") {
      requirePermission(admin, "commerce.promo.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCreatePromotionPayload(request);
      const requestHash = await hashCreatePromotionRequest(payload);
      const result = await commercePromotionsStore.create({
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
          mutationErrorMessage(result, "Promotion creation was not completed."),
        );
      }
      return json(
        {
          promotionId: String(result.promotionId),
          discountCodeId: String(result.discountCodeId),
          promotionStatus: String(result.promotionStatus),
          codeStatus: String(result.codeStatus),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    const promotionStatusId = matchCommercePromotionStatusPath(path);
    if (request.method === "POST" && promotionStatusId) {
      requirePermission(admin, "commerce.promo.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parsePromotionStatusPayload(request);
      const requestHash = await hashPromotionStatusRequest(
        promotionStatusId,
        payload,
      );
      const result = await commercePromotionsStore.setStatus({
        actorAccountId: accountId,
        promotionId: promotionStatusId,
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
            "Promotion status change was not completed.",
          ),
        );
      }
      return json(
        {
          promotionId: String(result.promotionId),
          previousStatus: String(result.previousStatus),
          status: String(result.status),
          noop: Boolean(result.noop),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    const promotionDetailId = matchCommercePromotionDetailPath(path);
    if (request.method === "GET" && promotionDetailId) {
      requirePermission(admin, "commerce.read");
      const result = await commercePromotionsStore.getDetail(
        promotionDetailId,
        admin.permissions.includes("security.audit.read"),
      );
      if (!result) {
        throw new ApiError(
          404,
          "commerce_promotion_not_found",
          "Commerce promotion was not found.",
        );
      }
      return json(
        {
          ...result,
          source: {
            kind: "canonical",
            label: "LifeMate Commerce promotion detail",
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (request.method === "PUT" && promotionDetailId) {
      requirePermission(admin, "commerce.promo.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseUpdatePromotionPayload(request);
      const requestHash = await hashUpdatePromotionRequest(
        promotionDetailId,
        payload,
      );
      const result = await commercePromotionsStore.update({
        actorAccountId: accountId,
        promotionId: promotionDetailId,
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
          mutationErrorMessage(result, "Promotion update was not completed."),
        );
      }
      return json(
        {
          promotionId: String(result.promotionId),
          status: String(result.status),
          discountCodeId: String(result.discountCodeId),
          codeStatus: String(result.codeStatus),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/commerce/transactions"
    ) {
      requirePermission(admin, "commerce.read");
      const query = parseCommerceTransactionsQuery(new URL(request.url));
      const result = await commerceTransactionsStore.list(query);
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          filters: {
            product: query.product,
            provider: query.provider,
            status: query.status,
            from: query.fromUtc,
            to: query.toUtc,
            q: query.referenceId,
          },
          source: {
            kind: "canonical",
            label: "LifeMate Commerce normalized ledger",
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const commerceRefundTransactionId = matchCommerceRefundRequestPath(path);
    if (request.method === "POST" && commerceRefundTransactionId) {
      requirePermission(admin, "commerce.refund");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCommerceRefundRequest(request);
      const requestHash = await hashCommerceRefundRequest(
        commerceRefundTransactionId,
        payload.reason,
      );
      const result = await commerceTransactionDetailStore.requestRefund({
        actorAccountId: accountId,
        transactionId: commerceRefundTransactionId,
        reason: payload.reason,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      if (result.httpStatus >= 400) {
        throw new ApiError(
          result.httpStatus,
          result.code,
          result.message ?? "Refund workflow request was not completed.",
        );
      }
      return json(
        {
          transactionId: result.transactionId,
          refundRequestId: result.refundRequestId,
          status: result.status,
          amountMinor: result.amountMinor,
          currency: result.currency,
          transactionStatus: result.transactionStatus,
          replayed: result.replayed,
          workflow: "HumanReview",
          providerActionExecuted: false,
        },
        result.httpStatus,
        origin,
      );
    }

    const commerceTransactionId = matchCommerceTransactionDetailPath(path);
    if (request.method === "GET" && commerceTransactionId) {
      requirePermission(admin, "commerce.read");
      const includeAudit = admin.permissions.includes("security.audit.read");
      const result = await commerceTransactionDetailStore.getDetail(
        commerceTransactionId,
        includeAudit,
      );
      if (!result) {
        throw new ApiError(
          404,
          "commerce_transaction_not_found",
          "Commerce transaction was not found.",
        );
      }
      const hasActiveWorkflow = result.refundRequests.some((item) =>
        ["PendingReview", "Approved", "Submitted"].includes(item.status)
      );
      return json(
        {
          ...result,
          refundCapability: getCommerceRefundCapability({
            normalizedStatus: result.transaction.normalizedStatus,
            hasActiveWorkflow,
            hasPermission: admin.permissions.includes("commerce.refund"),
          }),
          source: {
            kind: "canonical",
            label: "LifeMate Commerce normalized transaction detail",
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const commercePlanId = matchCommercePlanDetailPath(path);
    if (request.method === "GET" && commercePlanId) {
      requirePermission(admin, "commerce.read");
      const query = parseCommerceDetailQuery(new URL(request.url));
      const result = await commerceDetailStore.getPlan(commercePlanId, query);
      if (!result) {
        throw new ApiError(
          404,
          "commerce_plan_not_found",
          "Commerce plan was not found.",
        );
      }
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const commerceFeatureCode = matchCommerceEntitlementDetailPath(path);
    if (request.method === "GET" && commerceFeatureCode) {
      requirePermission(admin, "commerce.read");
      const query = parseCommerceDetailQuery(new URL(request.url));
      const result = await commerceDetailStore.getEntitlementFeature(
        commerceFeatureCode,
        query,
      );
      if (!result) {
        throw new ApiError(
          404,
          "commerce_feature_not_found",
          "Commerce feature was not found.",
        );
      }
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/relationships/overview"
    ) {
      requirePermission(admin, "relationships.read");
      const query = parseRelationshipOverviewQuery(new URL(request.url));
      const result = await relationshipOverviewStore.getOverview(query);
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          filters: {
            kind: query.kind,
            status: query.status,
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/relationships/ledger"
    ) {
      requirePermission(admin, "relationships.read");
      const query = parseRelationshipLedgerQuery(new URL(request.url));
      const result = await relationshipLedgerStore.getLedger(query);
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          filters: {
            kind: query.kind,
            status: query.status,
            from: query.from,
            to: query.to,
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/users") {
      requirePermission(admin, "users.read.basic");
      const query = parseUserDirectoryQuery(new URL(request.url));
      const result = await store.listUsers(query);
      return json(
        {
          items: result.items,
          page: query.page,
          pageSize: query.pageSize,
          total: result.total,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/support/tickets") {
      requirePermission(admin, "support.read");
      const query = parseSupportQueueQuery(new URL(request.url));
      const result = await supportQueueStore.list(query);
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          filters: {
            q: query.search,
            status: query.status,
            priority: query.priority,
            product: query.product,
            sla: query.sla,
            assignee: query.unassignedOnly
              ? "unassigned"
              : query.assigneeAccountId,
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/support/assignees") {
      requirePermission(admin, "support.write");
      return json(
        {
          items: await supportTicketDetailStore.listAssignees(),
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const supportTicketDetailId = matchSupportTicketDetailPath(path);
    if (request.method === "GET" && supportTicketDetailId) {
      requirePermission(admin, "support.read");
      const ticket = await supportTicketDetailStore.getDetail(
        supportTicketDetailId,
      );
      if (!ticket) {
        throw new ApiError(
          404,
          "support_ticket_not_found",
          "Support ticket was not found.",
        );
      }
      return json(
        {
          ticket,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const supportTicketEventsId = matchSupportTicketEventsPath(path);
    if (request.method === "GET" && supportTicketEventsId) {
      requirePermission(admin, "support.read");
      const ticket = await supportTicketDetailStore.getDetail(
        supportTicketEventsId,
      );
      if (!ticket) {
        throw new ApiError(
          404,
          "support_ticket_not_found",
          "Support ticket was not found.",
        );
      }
      const query = parseSupportTicketEventsQuery(new URL(request.url));
      const result = await supportTicketDetailStore.listEvents(
        supportTicketEventsId,
        query,
      );
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const supportTicketActionRoute = matchSupportTicketActionPath(path);
    if (request.method === "POST" && supportTicketActionRoute) {
      requirePermission(admin, "support.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseSupportTicketActionPayload(
        request,
        supportTicketActionRoute.action,
      );
      const requestHash = await hashSupportTicketActionRequest(
        supportTicketActionRoute.ticketId,
        supportTicketActionRoute.action,
        payload,
      );
      const result = await supportTicketDetailStore.execute({
        actorAccountId: accountId,
        ticketId: supportTicketActionRoute.ticketId,
        action: supportTicketActionRoute.action,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      if (result.httpStatus >= 400) {
        throw new ApiError(
          result.httpStatus,
          result.code,
          result.message ?? "Support ticket action was not completed.",
        );
      }
      return json(
        {
          ticketId: result.ticketId,
          status: result.status,
          priority: result.priority,
          assignedAdminAccountId: result.assignedAdminAccountId ?? null,
          lastActivityAtUtc: result.lastActivityAtUtc,
          action: result.action,
          replayed: result.replayed,
        },
        result.httpStatus,
        origin,
      );
    }

    const userActionRoute = matchUserAccountActionPath(path);
    if (request.method === "POST" && userActionRoute) {
      requirePermission(admin, "users.suspend");
      const idempotencyKey = requireIdempotencyKey(request);
      const body = await parseUserAccountActionRequest(request);
      const requestHash = await hashUserAccountActionRequest(
        userActionRoute.accountId,
        userActionRoute.action,
        body.reason,
      );
      const result = await userAccountActionStore.execute({
        actorAccountId: accountId,
        targetAccountId: userActionRoute.accountId,
        action: userActionRoute.action,
        reason: body.reason,
        correlationId,
        idempotencyKey,
        requestHash,
      });

      if (result.httpStatus >= 400) {
        throw new ApiError(
          result.httpStatus,
          result.code,
          result.message ?? "User account action was not completed.",
        );
      }

      return json(
        {
          accountId: result.accountId,
          action: result.action,
          previousStatus: result.previousStatus,
          status: result.status,
          replayed: result.replayed,
        },
        result.httpStatus,
        origin,
      );
    }

    const activityAccountId = matchUserActivityPath(path);
    if (request.method === "GET" && activityAccountId) {
      requirePermission(admin, "users.read.basic");
      requirePermission(admin, "security.audit.read");
      const base = await userDetailStore.getBase(activityAccountId);
      if (!base) {
        throw new ApiError(404, "user_not_found", "User was not found.");
      }
      const query = parseUserActivityQuery(new URL(request.url));
      const result = await userDetailStore.listAdminActivity(
        activityAccountId,
        query,
      );
      return json(
        {
          ...result,
          page: query.page,
          pageSize: query.pageSize,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const detailAccountId = matchUserDetailPath(path);
    if (request.method === "GET" && detailAccountId) {
      requirePermission(admin, "users.read.basic");
      const base = await userDetailStore.getBase(detailAccountId);
      if (!base) {
        throw new ApiError(404, "user_not_found", "User was not found.");
      }

      const permissions = getUserDetailSectionPermissions(admin.permissions);
      const personId = base.person?.id ?? null;
      const [products, commerce, relationships, adminActivity] = await Promise
        .all([
          optionalSection(
            true,
            () => userDetailStore.listEnrollments(detailAccountId),
            (value) => value.length === 0,
            correlationId,
            "products",
          ),
          optionalSection(
            permissions.commerce,
            () => userDetailStore.getCommerce(detailAccountId, personId),
            (value) =>
              value.subscriptions.length === 0 &&
              value.entitlements.length === 0,
            correlationId,
            "commerce",
          ),
          optionalSection(
            permissions.relationships,
            () => userDetailStore.getRelationships(personId),
            (value) => value.length === 0,
            correlationId,
            "relationships",
          ),
          optionalSection(
            permissions.adminActivity,
            () => userDetailStore.getAdminActivity(detailAccountId),
            (value) => value.total === 0,
            correlationId,
            "adminActivity",
          ),
        ]);

      return json(
        {
          account: {
            state: "ready",
            data: userDetailAccountData(base),
          },
          person: base.person
            ? { state: "ready", data: base.person }
            : { state: "empty" },
          products,
          commerce,
          relationships,
          adminActivity,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/audit") {
      requirePermission(admin, "security.audit.read");
      const query = parseAuditQuery(new URL(request.url));
      const result = await store.listAudit(query);
      return json(
        {
          ...result,
          filters: { from: query.fromUtc, to: query.toUtc },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    throw new ApiError(
      404,
      "route_not_found",
      "Admin API route was not found.",
    );
  } catch (error) {
    if (error instanceof ApiError) {
      return problem(
        error.status,
        error.code,
        error.message,
        correlationId,
        origin,
      );
    }
    if (isPostgresUnavailable(error)) {
      console.warn("LifeMate Admin database temporarily unavailable", {
        correlationId,
        method: request.method,
        path,
        ...safeError(error),
      });
      return problem(
        503,
        "database_busy",
        "Database is temporarily unavailable.",
        correlationId,
        origin,
      );
    }
    console.error("Unhandled LifeMate Admin API error", {
      correlationId,
      method: request.method,
      path,
      ...safeError(error),
    });
    return problem(
      500,
      "internal_error",
      "The request could not be completed.",
      correlationId,
      origin,
    );
  }
});
