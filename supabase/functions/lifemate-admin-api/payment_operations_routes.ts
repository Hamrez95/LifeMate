import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  hashPaymentOperation,
  parseCorrectionExecute,
  parseCorrectionPreview,
  parseReconciliationCase,
  parseRefundRequestV2,
  parseRefundSubmit,
  parseRenewalIntent,
} from "./payment_operations.ts";
import { createPaymentOperationsStore } from "./payment_operations_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

const uuid =
  "[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const refundSubmitPattern = new RegExp(
  `^/api/v1/commerce/refunds/(${uuid})/actions/submit$`,
  "i",
);

function status(result: Record<string, unknown>): number {
  const value = Number(result.httpStatus);
  if (!Number.isInteger(value) || value < 100 || value > 599) {
    throw new ApiError(
      503,
      "payment_operation_unavailable",
      "Payment operation returned an invalid status.",
    );
  }
  if (value >= 400) {
    throw new ApiError(
      value,
      String(result.code ?? "payment_operation_failed"),
      typeof result.message === "string"
        ? result.message
        : "Payment operation was not completed.",
    );
  }
  return value;
}

function limit(url: URL): number {
  const raw = url.searchParams.get("limit");
  if (raw == null) return 100;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 200) {
    throw new ApiError(
      400,
      "limit_invalid",
      "limit must be between 1 and 200.",
    );
  }
  return value;
}

export function createPaymentOperationsRouteHandler(databaseUrl: string) {
  const store = createPaymentOperationsStore(databaseUrl);

  return async function handlePaymentOperationsRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/commerce/refunds") {
      requirePermission(admin, "commerce.refund.read");
      const pageLimit = limit(new URL(request.url));
      return json(
        {
          items: await store.listRefunds(pageLimit),
          limit: pageLimit,
          providerResultIsFactOnly: true,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" && path === "/api/v1/commerce/refunds/requests"
    ) {
      requirePermission(admin, "commerce.refund.request");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseRefundRequestV2(request);
      const requestHash = await hashPaymentOperation({
        action: "refund.request",
        ...payload,
      });
      const result = await store.requestRefund({
        actorAccountId: accountId,
        ...payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return json(result, status(result), origin);
    }

    const refundSubmit = refundSubmitPattern.exec(path)?.[1] ?? null;
    if (request.method === "POST" && refundSubmit) {
      requirePermission(admin, "commerce.refund.execute");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseRefundSubmit(request);
      const requestHash = await hashPaymentOperation({
        action: "refund.submit",
        refundRequestId: refundSubmit,
        ...payload,
      });
      const result = await store.submitRefund({
        actorAccountId: accountId,
        refundRequestId: refundSubmit,
        ...payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return json(result, status(result), origin);
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/commerce/reconciliation/cases"
    ) {
      requirePermission(admin, "commerce.reconciliation.read");
      const pageLimit = limit(new URL(request.url));
      return json(
        {
          items: await store.listReconciliationCases(pageLimit),
          limit: pageLimit,
          providerFactsPreserved: true,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/reconciliation/cases"
    ) {
      requirePermission(admin, "commerce.reconciliation.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseReconciliationCase(request);
      const requestHash = await hashPaymentOperation({
        action: "reconciliation.open",
        ...payload,
      });
      const result = await store.openReconciliation({
        actorAccountId: accountId,
        ...payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return json(result, status(result), origin);
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/reconciliation/corrections/preview"
    ) {
      requirePermission(admin, "commerce.reconciliation.write");
      const payload = await parseCorrectionPreview(request);
      const result = await store.previewCorrection(payload);
      return json(
        {
          ...result,
          approvalRequestTemplate: {
            requestType: "commerce_transaction_correction",
            targetType: "reconciliation_case",
            targetId: payload.caseId,
            before: result.before,
            delta: result.delta,
            after: result.after,
            reason: payload.reason,
          },
        },
        status(result),
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/reconciliation/corrections/execute"
    ) {
      requirePermission(admin, "commerce.reconciliation.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCorrectionExecute(request);
      const requestHash = await hashPaymentOperation({
        action: "reconciliation.correct",
        ...payload,
      });
      const result = await store.executeCorrection({
        actorAccountId: accountId,
        ...payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return json(result, status(result), origin);
    }

    if (request.method === "GET" && path === "/api/v1/commerce/churn") {
      requirePermission(admin, "commerce.churn.read");
      const pageLimit = limit(new URL(request.url));
      return json(
        {
          items: await store.listChurn(pageLimit),
          limit: pageLimit,
          entitlementEndsAtPeriodEnd: true,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/subscriptions/renewal-intent"
    ) {
      requirePermission(admin, "commerce.churn.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseRenewalIntent(request);
      const requestHash = await hashPaymentOperation({
        action: "subscription.renewal-intent",
        ...payload,
      });
      const result = await store.setRenewalIntent({
        actorAccountId: accountId,
        ...payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return json(result, status(result), origin);
    }

    return null;
  };
}
