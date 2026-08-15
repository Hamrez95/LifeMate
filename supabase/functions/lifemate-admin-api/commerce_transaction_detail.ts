import { ApiError, requireUuid } from "./validation.ts";

export type CommerceRefundRequestPayload = {
  reason: string;
};

export type CommerceRefundRequestResult = {
  httpStatus: number;
  code: string;
  message?: string;
  transactionId?: string;
  refundRequestId?: string;
  status?: string;
  amountMinor?: string;
  currency?: string;
  transactionStatus?: string;
  replayed: boolean;
};

const DETAIL_PATH = /^\/api\/v1\/commerce\/transactions\/([^/]+)$/i;
const REFUND_REQUEST_PATH =
  /^\/api\/v1\/commerce\/transactions\/([^/]+)\/actions\/refund-request$/i;

export function matchCommerceTransactionDetailPath(path: string): string | null {
  const match = DETAIL_PATH.exec(path);
  return match ? requireUuid(match[1], "transactionId") : null;
}

export function matchCommerceRefundRequestPath(path: string): string | null {
  const match = REFUND_REQUEST_PATH.exec(path);
  return match ? requireUuid(match[1], "transactionId") : null;
}

export async function parseCommerceRefundRequest(
  request: Request,
): Promise<CommerceRefundRequestPayload> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be valid JSON.",
    );
  }

  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be an object.",
    );
  }

  const reason = (body as Record<string, unknown>).reason;
  if (typeof reason !== "string") {
    throw new ApiError(
      400,
      "refund_reason_required",
      "A refund workflow reason is required.",
    );
  }

  const normalized = reason.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "refund_reason_invalid",
      "Refund workflow reason must contain between 10 and 1000 characters.",
    );
  }

  return { reason: normalized };
}

export async function hashCommerceRefundRequest(
  transactionId: string,
  reason: string,
): Promise<string> {
  const canonical = `v1\n${transactionId}\nrefund-request\n${reason}`;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export function assertCommerceRefundRequestResult(
  value: unknown,
): CommerceRefundRequestResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "refund_workflow_unavailable",
      "Refund workflow result was unavailable.",
    );
  }

  const row = value as Record<string, unknown>;
  if (
    !Number.isInteger(row.httpStatus) ||
    typeof row.code !== "string" ||
    typeof row.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "refund_workflow_unavailable",
      "Refund workflow result was invalid.",
    );
  }

  return row as unknown as CommerceRefundRequestResult;
}
