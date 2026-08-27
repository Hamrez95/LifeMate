import { ApiError, requireUuid } from "./validation.ts";

async function objectBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be a JSON object.",
    );
  }
}

function text(value: unknown, field: string, min: number, max: number): string {
  if (typeof value !== "string") {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  const result = value.trim();
  if (result.length < min || result.length > max) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return result;
}

function integer(value: unknown, field: string, min: number): number {
  const number = typeof value === "string" && /^\d+$/.test(value)
    ? Number(value)
    : value;
  if (!Number.isSafeInteger(number) || Number(number) < min) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return Number(number);
}

function positiveBigintText(value: unknown, field: string): string {
  if (typeof value !== "string" && typeof value !== "number") {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  const raw = String(value).trim();
  if (!/^[1-9]\d{0,18}$/.test(raw)) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  try {
    const parsed = BigInt(raw);
    if (parsed > 9223372036854775807n) throw new Error("overflow");
  } catch {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return raw;
}

function key(value: unknown, field: string): string {
  const result = text(value, field, 3, 80).toLowerCase();
  if (!/^[a-z][a-z0-9._-]{2,79}$/.test(result)) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return result;
}

function booleanValue(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new ApiError(400, `${field}_invalid`, `${field} must be boolean.`);
  }
  return value;
}

function correctionPayload(body: Record<string, unknown>) {
  return {
    caseId: requireUuid(String(body.caseId ?? ""), "caseId"),
    correctionType: text(body.correctionType, "correction_type", 5, 40),
    correctedStatus: body.correctedStatus == null
      ? null
      : text(body.correctedStatus, "corrected_status", 5, 20),
    annotationCode: body.annotationCode == null
      ? null
      : key(body.annotationCode, "annotation_code"),
    reason: text(body.reason, "reason", 10, 1000),
  };
}

export async function parseRefundRequestV2(request: Request) {
  const body = await objectBody(request);
  return {
    transactionId: requireUuid(
      String(body.transactionId ?? ""),
      "transactionId",
    ),
    amountMinor: positiveBigintText(body.amountMinor, "amount_minor"),
    reason: text(body.reason, "reason", 10, 1000),
  };
}

export async function parseRefundSubmit(request: Request) {
  const body = await objectBody(request);
  return {
    expectedRefundVersion: integer(
      body.expectedRefundVersion,
      "expected_refund_version",
      1,
    ),
    approvalExpectedVersion: integer(
      body.approvalExpectedVersion,
      "approval_expected_version",
      1,
    ),
  };
}

export async function parseReconciliationCase(request: Request) {
  const body = await objectBody(request);
  return {
    transactionId: body.transactionId == null
      ? null
      : requireUuid(String(body.transactionId), "transactionId"),
    caseType: text(body.caseType, "case_type", 5, 40),
    reason: text(body.reason, "reason", 10, 1000),
  };
}

export async function parseCorrectionPreview(request: Request) {
  return correctionPayload(await objectBody(request));
}

export async function parseCorrectionExecute(request: Request) {
  const body = await objectBody(request);
  return {
    ...correctionPayload(body),
    approvalRequestId: requireUuid(
      String(body.approvalRequestId ?? ""),
      "approvalRequestId",
    ),
    approvalExpectedVersion: integer(
      body.approvalExpectedVersion,
      "approval_expected_version",
      1,
    ),
  };
}

export async function parseRenewalIntent(request: Request) {
  const body = await objectBody(request);
  return {
    subscriptionId: requireUuid(
      String(body.subscriptionId ?? ""),
      "subscriptionId",
    ),
    expectedVersion: integer(body.expectedVersion, "expected_version", 1),
    cancelAtPeriodEnd: booleanValue(
      body.cancelAtPeriodEnd,
      "cancel_at_period_end",
    ),
    reasonCode: key(body.reasonCode, "reason_code"),
    reasonText: body.reasonText == null
      ? null
      : text(body.reasonText, "reason_text", 1, 1000),
  };
}

function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{$
    {
      Object.entries(value as Record<string, unknown>)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`)
        .join(",")
    }
  }}`.replace(/\$\s*\{\s*/, "").replace(/\s*\}$/, "");
}

export async function hashPaymentOperation(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(stable(value)),
  );
  return [...new Uint8Array(digest)]
    .map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}
