import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import { createSupportConversationAdminStore } from "./support_conversation_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export function createSupportConversationAdminRouteHandler(databaseUrl: string) {
  const store = createSupportConversationAdminStore(databaseUrl);

  return async function supportConversationAdminRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    const operationsMatch = path.match(
      /^\/api\/v1\/support\/tickets\/([0-9a-f-]{36})\/conversation\/operations$/i,
    );
    if (operationsMatch) {
      const ticketId = requiredUuid(operationsMatch[1]);
      if (request.method !== "GET") return null;
      requirePermission(admin, "support.read");
      const operations = await store.listOperations(ticketId);
      return json({
        ...operations,
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    const escalationMatch = path.match(
      /^\/api\/v1\/support\/tickets\/([0-9a-f-]{36})\/conversation\/escalations$/i,
    );
    if (escalationMatch) {
      const ticketId = requiredUuid(escalationMatch[1]);
      if (request.method !== "POST") return null;
      requirePermission(admin, "support.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await requiredObject(request);
      const targetRoleCode = requiredCode(payload.targetRoleCode, "support_escalation_role_invalid");
      const safeReason = requiredSafeReason(payload.safeReason);
      const requestHash = await sha256Hex(JSON.stringify({ ticketId, targetRoleCode, safeReason }));
      const result = await store.escalate({
        actorAccountId: accountId,
        ticketId,
        targetRoleCode,
        safeReason,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return mutationResponse(result, origin, "support_escalation_failed");
    }

    const linkMatch = path.match(
      /^\/api\/v1\/support\/tickets\/([0-9a-f-]{36})\/conversation\/links$/i,
    );
    if (linkMatch) {
      const ticketId = requiredUuid(linkMatch[1]);
      if (request.method !== "POST") return null;
      requirePermission(admin, "support.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await requiredObject(request);
      const linkKind = requiredLinkKind(payload.linkKind);
      const referenceCode = requiredReference(payload.referenceCode);
      const requestHash = await sha256Hex(JSON.stringify({ ticketId, linkKind, referenceCode }));
      const result = await store.linkReference({
        actorAccountId: accountId,
        ticketId,
        linkKind,
        referenceCode,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return mutationResponse(result, origin, "support_reference_failed");
    }

    const match = path.match(
      /^\/api\/v1\/support\/tickets\/([0-9a-f-]{36})\/conversation(?:\/messages)?$/i,
    );
    if (!match) return null;
    const ticketId = requiredUuid(match[1]);

    if (request.method === "GET") {
      requirePermission(admin, "support.read");
      const url = new URL(request.url);
      const beforeAt = optionalTimestamp(url.searchParams.get("beforeAt"));
      const afterAt = optionalTimestamp(url.searchParams.get("afterAt"));
      if (beforeAt && afterAt) {
        throw new ApiError(
          400,
          "support_cursor_conflict",
          "Use either beforeAt or afterAt, not both.",
        );
      }
      const limit = boundedLimit(url.searchParams.get("limit"));
      const items = await store.list(ticketId, beforeAt, afterAt, limit);
      return json({
        items,
        pageSize: limit,
        polling: {
          afterAt: items.length === 0 ? afterAt : items[0].createdAtUtc,
        },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "POST") {
      requirePermission(admin, "support.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await requiredObject(request);
      const body = requiredMessage(payload.body);
      const clientMessageId = requiredUuid(payload.clientMessageId);
      const requestHash = await sha256Hex(JSON.stringify({
        ticketId,
        body,
        clientMessageId,
      }));
      const result = await store.send({
        actorAccountId: accountId,
        ticketId,
        body,
        clientMessageId,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return mutationResponse(result, origin, "support_message_failed");
    }

    return null;
  };
}

async function requiredObject(request: Request): Promise<Record<string, unknown>> {
  const payload = await request.json().catch(() => null);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new ApiError(400, "invalid_json", "Request body is invalid.");
  }
  return payload as Record<string, unknown>;
}

function mutationResponse(
  result: Record<string, unknown>,
  origin: string | null,
  fallbackCode: string,
): Response {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(503, "support_operation_unavailable", "Support operation returned an invalid status.");
  }
  if (status >= 400) {
    throw new ApiError(
      status,
      String(result.code ?? fallbackCode),
      typeof result.message === "string" ? result.message : "Support operation failed.",
    );
  }
  return json(result, status, origin);
}

function requiredUuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  ) {
    throw new ApiError(400, "invalid_uuid", "Identifier is invalid.");
  }
  return value.toLowerCase();
}

function requiredMessage(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "support_message_invalid", "Message is invalid.");
  }
  const result = value.trim();
  if (!result || result.length > 4000 || new TextEncoder().encode(result).byteLength > 12000) {
    throw new ApiError(400, "support_message_invalid", "Message is invalid.");
  }
  return result;
}

function requiredCode(value: unknown, code: string): string {
  if (typeof value !== "string") throw new ApiError(400, code, "Code is invalid.");
  const result = value.trim().toLowerCase();
  if (!/^[a-z0-9._-]{2,64}$/.test(result)) throw new ApiError(400, code, "Code is invalid.");
  return result;
}

function requiredSafeReason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "support_escalation_reason_invalid", "Escalation reason is invalid.");
  }
  const result = value.trim();
  if (result.length < 5 || result.length > 800) {
    throw new ApiError(400, "support_escalation_reason_invalid", "Escalation reason is invalid.");
  }
  return result;
}

function requiredLinkKind(value: unknown): string {
  if (typeof value !== "string" || !["ProductIssue", "EngineeringIssue", "Incident", "Other"].includes(value)) {
    throw new ApiError(400, "support_link_invalid", "Link kind is invalid.");
  }
  return value;
}

function requiredReference(value: unknown): string {
  if (typeof value !== "string") throw new ApiError(400, "support_link_invalid", "Reference is invalid.");
  const result = value.trim();
  if (!result || result.length > 180 || /^https?:\/\//i.test(result)) {
    throw new ApiError(400, "support_link_invalid", "Reference is invalid.");
  }
  return result;
}

function optionalTimestamp(value: string | null): string | null {
  if (!value) return null;
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new ApiError(400, "invalid_timestamp", "Timestamp is invalid.");
  }
  return date.toISOString();
}

function boundedLimit(value: string | null): number {
  if (!value) return 50;
  if (!/^\d{1,3}$/.test(value)) {
    throw new ApiError(400, "invalid_page_size", "Page size is invalid.");
  }
  const parsed = Number(value);
  if (parsed < 1 || parsed > 100) {
    throw new ApiError(400, "invalid_page_size", "Page size is invalid.");
  }
  return parsed;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}
