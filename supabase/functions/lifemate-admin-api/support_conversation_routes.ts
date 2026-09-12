import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import { createSupportConversationAdminStore } from "./support_conversation_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export function createSupportConversationAdminRouteHandler(
  databaseUrl: string,
) {
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
      return json(
        {
          items,
          pageSize: limit,
          polling: {
            afterAt: items.length === 0 ? afterAt : items[0].createdAtUtc,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "POST") {
      requirePermission(admin, "support.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await request.json().catch(() => null);
      if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
        throw new ApiError(400, "invalid_json", "Request body is invalid.");
      }
      const body = requiredMessage((payload as Record<string, unknown>).body);
      const clientMessageId = requiredUuid(
        (payload as Record<string, unknown>).clientMessageId,
      );
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
      const status = Number(result.httpStatus);
      if (!Number.isInteger(status) || status < 100 || status > 599) {
        throw new ApiError(
          503,
          "support_conversation_unavailable",
          "Support conversation returned an invalid status.",
        );
      }
      if (status >= 400) {
        throw new ApiError(
          status,
          String(result.code ?? "support_message_failed"),
          typeof result.message === "string"
            ? result.message
            : "Support message was not sent.",
        );
      }
      return json(
        {
          ticketId: String(result.ticketId),
          messageId: String(result.messageId),
          createdAtUtc: String(result.createdAtUtc),
          replayed: Boolean(result.replayed),
        },
        status,
        origin,
      );
    }

    return null;
  };
}

function requiredUuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
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
  if (
    !result || result.length > 4000 ||
    new TextEncoder().encode(result).byteLength > 12000
  ) {
    throw new ApiError(400, "support_message_invalid", "Message is invalid.");
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
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}
