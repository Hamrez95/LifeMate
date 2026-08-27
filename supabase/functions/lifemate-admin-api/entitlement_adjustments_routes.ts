import postgres from "postgres";
import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  hashEntitlementAdjustmentPayload,
  parseEntitlementAdjustmentPayload,
} from "./entitlement_adjustments.ts";
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

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ACCOUNT_HISTORY = /^\/api\/v1\/commerce\/accounts\/([^/]+)\/entitlement-adjustments$/i;

function workflowStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "entitlement_adjustment_unavailable",
      "Entitlement adjustment workflow returned an invalid status.",
    );
  }
  if (status >= 400) {
    throw new ApiError(
      status,
      String(result.code ?? "entitlement_adjustment_failed"),
      typeof result.message === "string"
        ? result.message
        : "Entitlement adjustment was not completed.",
    );
  }
  return status;
}

function historyAccount(path: string, request: Request): string | null {
  const match = ACCOUNT_HISTORY.exec(path);
  const candidate = match?.[1] ??
    (path === "/api/v1/commerce/entitlement-adjustments"
      ? new URL(request.url).searchParams.get("accountId")
      : null);
  if (candidate == null) return null;
  if (!UUID.test(candidate)) {
    throw new ApiError(400, "account_id_invalid", "accountId must be a UUID.");
  }
  return candidate.toLowerCase();
}

export function createEntitlementAdjustmentRouteHandler(databaseUrl: string) {
  const sql = postgres(databaseUrl, { max: 1, prepare: false });

  return async function handleEntitlementAdjustmentRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (request.method === "GET") {
      const targetAccountId = historyAccount(path, request);
      if (targetAccountId) {
        requirePermission(admin, "commerce.entitlement.adjust.read");
        const rows = await sql`
          select id,target_account_id,target_type,target_id,action,schedule_mode,
                 schedule_amount,exact_expires_at_utc,before_json,after_json,
                 approval_request_id,abuse_decision_id,executed_by_account_id,
                 reason,correlation_id,executed_at_utc
          from commerce.entitlement_adjustments
          where target_account_id=${targetAccountId}::uuid
          order by executed_at_utc desc,id desc
          limit 100
        `;
        return json(
          {
            accountId: targetAccountId,
            items: rows,
            source: { kind: "canonical", label: "LifeMate entitlement adjustment ledger" },
            freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
          },
          200,
          origin,
        );
      }
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/entitlement-adjustments/preview"
    ) {
      requirePermission(admin, "commerce.entitlement.adjust.request");
      const payload = await parseEntitlementAdjustmentPayload(request);
      const rows = await sql`
        select commerce.preview_entitlement_adjustment_v2(
          ${payload.accountId}::uuid,
          ${payload.targetType}::character varying,
          ${payload.targetId}::uuid,
          ${payload.action}::character varying,
          ${payload.scheduleMode}::character varying,
          ${payload.scheduleAmount}::integer,
          ${payload.exactExpiresAtUtc}::timestamptz
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      const status = workflowStatus(result);
      return json(
        {
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
        },
        status,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/entitlement-adjustments/actions/execute"
    ) {
      requirePermission(admin, "commerce.entitlement.adjust.execute");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseEntitlementAdjustmentPayload(request);
      const requestHash = await hashEntitlementAdjustmentPayload(payload);
      const rows = await sql`
        select commerce.execute_entitlement_adjustment_v2(
          ${accountId}::uuid,
          ${payload.accountId}::uuid,
          ${payload.targetType}::character varying,
          ${payload.targetId}::uuid,
          ${payload.action}::character varying,
          ${payload.scheduleMode}::character varying,
          ${payload.scheduleAmount}::integer,
          ${payload.exactExpiresAtUtc}::timestamptz,
          ${payload.reason}::character varying,
          ${payload.confirmed}::boolean,
          ${payload.approvalRequestId}::uuid,
          ${payload.approvalExpectedVersion}::bigint,
          ${correlationId}::uuid,
          ${idempotencyKey}::character varying,
          ${requestHash}::character varying
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      return json(result, workflowStatus(result), origin);
    }

    return null;
  };
}
