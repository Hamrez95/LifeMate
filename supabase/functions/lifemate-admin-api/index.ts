import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { getAnalyticsCatalog } from "./analytics_catalog.ts";
import { createAnalyticsKpiStore } from "./analytics_kpi_service.ts";
import { parseAnalyticsKpiQuery } from "./analytics_kpis.ts";
import { authenticate, requireAal2 } from "./auth.ts";
import { requirePermission } from "./authorization.ts";
import { parseCommerceOverviewQuery } from "./commerce.ts";
import {
  matchCommerceEntitlementDetailPath,
  matchCommercePlanDetailPath,
  parseCommerceDetailQuery,
} from "./commerce_detail.ts";
import { createCommerceDetailStore } from "./commerce_detail_service.ts";
import { createCommerceOverviewStore } from "./commerce_service.ts";
import { isPostgresUnavailable } from "./database_client.ts";
import { parseUserDirectoryQuery } from "./directory.ts";
import {
  assertAllowedOrigin,
  json,
  preflight,
  problem,
  safeError,
} from "./http.ts";
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
} from "./user_detail.ts";
import { getUserDetailSectionPermissions } from "./user_detail_permissions.ts";
import { createUserDetailStore } from "./user_detail_store.ts";
import {
  ApiError,
  boundedInteger,
  normalizePath,
  requireIdempotencyKey,
} from "./validation.ts";

const config = await loadRuntimeConfig();
const store = createAdminStore(config.databaseUrl);
const userDetailStore = createUserDetailStore(config.databaseUrl);
const userAccountActionStore = createUserAccountActionStore(config.databaseUrl);
const analyticsKpiStore = createAnalyticsKpiStore(config.databaseUrl);
const commerceOverviewStore = createCommerceOverviewStore(config.databaseUrl);
const commerceDetailStore = createCommerceDetailStore(config.databaseUrl);
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
            data: {
              id: base.accountId,
              status: base.status,
              createdAtUtc: base.createdAtUtc,
            },
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
      const url = new URL(request.url);
      const limit = boundedInteger(url.searchParams.get("limit"), 50, 1, 200);
      return json({ events: await store.listAudit(limit) }, 200, origin);
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
