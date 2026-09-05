import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  hashCreateApprovalRequest,
  hashDecideApprovalRequest,
  matchApprovalDecisionPath,
  matchApprovalRequestPath,
  parseCreateApprovalRequest,
  parseDecideApprovalRequest,
} from "./approval_requests.ts";
import { createApprovalRequestStore } from "./approval_requests_service.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

const STATUSES = new Set([
  "Pending",
  "Approved",
  "Rejected",
  "Expired",
  "Executed",
  "Cancelled",
]);
const REQUEST_TYPE = /^[a-z][a-z0-9._-]{2,79}$/;

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "approval_workflow_unavailable",
      "Approval workflow returned an invalid status.",
    );
  }
  if (status >= 400) {
    throw new ApiError(
      status,
      String(result.code),
      typeof result.message === "string"
        ? result.message
        : "Approval workflow was not completed.",
    );
  }
  return status;
}

function listQuery(url: URL) {
  const rawStatus = url.searchParams.get("status");
  const status = rawStatus?.trim() || null;
  if (status && !STATUSES.has(status)) {
    throw new ApiError(
      400,
      "approval_status_invalid",
      "status filter is invalid.",
    );
  }
  const rawType = url.searchParams.get("requestType");
  const requestType = rawType?.trim().toLowerCase() || null;
  if (requestType && !REQUEST_TYPE.test(requestType)) {
    throw new ApiError(
      400,
      "approval_request_type_invalid",
      "requestType filter is invalid.",
    );
  }
  const rawLimit = url.searchParams.get("limit");
  const limit = rawLimit === null ? 50 : Number(rawLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new ApiError(
      400,
      "approval_limit_invalid",
      "limit must be an integer between 1 and 100.",
    );
  }
  return { status, requestType, limit };
}

export function createApprovalRequestRouteHandler(databaseUrl: string) {
  const store = createApprovalRequestStore(databaseUrl);
  return async function handleApprovalRequestRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (
      request.method === "GET" &&
      path === "/api/v1/operations/approval-requests"
    ) {
      requirePermission(admin, "operations.approval.read");
      const query = listQuery(new URL(request.url));
      const items = await store.list(
        query.status,
        query.requestType,
        query.limit,
      );
      return json(
        {
          items,
          limit: query.limit,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/operations/approval-requests"
    ) {
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCreateApprovalRequest(request);
      const result = await store.create({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashCreateApprovalRequest(payload),
      });
      return json(result, mutationStatus(result), origin);
    }

    const decision = matchApprovalDecisionPath(path);
    if (request.method === "POST" && decision) {
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseDecideApprovalRequest(
        request,
        decision.decision,
      );
      const result = await store.decide({
        actorAccountId: accountId,
        id: decision.id,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashDecideApprovalRequest(decision.id, payload),
      });
      return json(result, mutationStatus(result), origin);
    }

    const id = matchApprovalRequestPath(path);
    if (request.method === "GET" && id) {
      requirePermission(admin, "operations.approval.read");
      const detail = await store.get(id);
      if (!detail) {
        throw new ApiError(
          404,
          "approval_request_not_found",
          "Approval request was not found.",
        );
      }
      return json(detail, 200, origin);
    }

    return null;
  };
}
