import postgres from "postgres";
import { type AdminCapabilitySnapshot, requirePermission } from "./authorization.ts";
import {
  hashEntitlementAdjustmentPayload,
  parseEntitlementAdjustmentPayload,
} from "./commerce_entitlement_adjustments.ts";
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

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function statusFrom(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(503, "entitlement_adjustment_unavailable", "Entitlement adjustment workflow returned an invalid status.");
  }
  if (status >= 400) {
    throw new ApiError(status, String(result.code), typeof result.message === "string" ? result.message : "Entitlement adjustment failed.");
  }
  return status;
}

export function createCommerceEntitlementAdjustmentRouteHandler(databaseUrl: string) {
  const sql = postgres(databaseUrl, { max: 1, prepare: false });

  return async function handleCommerceEntitlementAdjustmentRoute(context: Context): Promise<Response | null> {
    const { request, path, accountId: actorAccountId, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/commerce/entitlement-adjustments") {
      requirePermission(admin, "commerce.entitlement.adjust.read");
      const url = new URL(request.url);
      const targetAccountId = url.searchParams.get("accountId") ?? "";
      if (!uuidPattern.test(targetAccountId)) throw new ApiError(400, "account_id_invalid", "accountId is required and must be a UUID.");
      const rows = await sql`
        select id,target_account_id,target_type,target_id,action,schedule_mode,schedule_amount,
               exact_expires_at_utc,before_json,after_json,approval_request_id,abuse_decision_id,
               executed_by_account_id,reason,executed_at_utc
        from commerce.entitlement_adjustments
        where target_account_id=${targetAccountId}::uuid
        order by executed_at_utc desc,id desc
        limit 200
      `;
      return json({
        items: rows,
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "POST" && path === "/api/v1/commerce/entitlement-adjustments/preview") {
      requirePermission(admin, "commerce.entitlement.adjust.request");
      const payload = await parseEntitlementAdjustmentPayload(request);
      const rows = await sql`
        select commerce.preview_entitlement_adjustment(
          ${payload.accountId}::uuid,${payload.targetType}::varchar,${payload.targetId}::uuid,
          ${payload.action}::varchar,${payload.scheduleMode}::varchar,${payload.scheduleAmount}::integer,
          ${payload.exactExpiresAtUtc}::timestamptz
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      const status = statusFrom(result);
      return json({
        ...result,
        approvalRequestTemplate: {
          requestType: "commerce.entitlement.adjustment",
          targetType: "commerce_entitlement_adjustment",
          targetId: payload.accountId,
          before: result.before,
          delta: result.delta,
          after: result.after,
          reason: payload.reason,
        },
      }, status, origin);
    }

    if (request.method === "POST" && path === "/api/v1/commerce/entitlement-adjustments/actions/execute") {
      requirePermission(admin, "commerce.entitlement.adjust.execute");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseEntitlementAdjustmentPayload(request);
      const requestHash = await hashEntitlementAdjustmentPayload(payload);
      const rows = await sql`
        select commerce.execute_entitlement_adjustment(
          ${actorAccountId}::uuid,${payload.accountId}::uuid,${payload.targetType}::varchar,${payload.targetId}::uuid,
          ${payload.action}::varchar,${payload.scheduleMode}::varchar,${payload.scheduleAmount}::integer,
          ${payload.exactExpiresAtUtc}::timestamptz,${payload.reason}::varchar,
          ${payload.approvalRequestId}::uuid,${payload.approvalExpectedVersion}::bigint,
          ${correlationId}::uuid,${idempotencyKey}::varchar,${requestHash}::varchar
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      return json(result, statusFrom(result), origin);
    }

    return null;
  };
}
