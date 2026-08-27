import { json } from "./http.ts";
import { ApiError, readJsonObject } from "./validation.ts";
import type { createSupportConversationStore } from "./support_conversations.ts";

type Store = ReturnType<typeof createSupportConversationStore>;

export function createSupportConversationRouteHandler(store: Store) {
  return async (input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> => {
    const { request, path, appUserId } = input;

    if (request.method === "POST" && path === "/api/v1/support/conversations") {
      const body = await readJsonObject(request);
      return json(await store.open(appUserId, {
        productCode: optionalProductCode(body.productCode),
        category: optionalCategory(body.category) ?? "general",
        body: requiredMessage(body.body),
        clientMessageId: requiredUuid(body.clientMessageId),
      }), 201);
    }

    const match = path.match(
      /^\/api\/v1\/support\/conversations\/([0-9a-f-]{36})(?:\/(messages|read))?$/i,
    );
    if (!match) return null;
    const ticketId = requiredUuid(match[1]);
    const suffix = match[2] ?? null;

    if (request.method === "GET" && suffix === null) {
      const url = new URL(request.url);
      const beforeAt = optionalTimestamp(url.searchParams.get("beforeAt"));
      const limit = boundedLimit(url.searchParams.get("limit"));
      return json({
        items: await store.list(appUserId, ticketId, beforeAt, limit),
      });
    }

    if (request.method === "POST" && suffix === "messages") {
      const body = await readJsonObject(request);
      return json(await store.send(appUserId, ticketId, {
        body: requiredMessage(body.body),
        clientMessageId: requiredUuid(body.clientMessageId),
      }), 201);
    }

    if (request.method === "POST" && suffix === "read") {
      const body = await readJsonObject(request);
      return json(
        await store.markRead(
          appUserId,
          ticketId,
          requiredUuid(body.messageId),
        ),
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
  const text = value.trim();
  if (
    !text || text.length > 4000 ||
    new TextEncoder().encode(text).byteLength > 12000
  ) {
    throw new ApiError(400, "support_message_invalid", "Message is invalid.");
  }
  return text;
}

function optionalProductCode(value: unknown): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "support_product_invalid",
      "Support product is invalid.",
    );
  }
  const result = value.trim().toLowerCase();
  if (
    !result || result.length > 64 ||
    !/^[a-z0-9][a-z0-9_.:-]*$/.test(result)
  ) {
    throw new ApiError(
      400,
      "support_product_invalid",
      "Support product is invalid.",
    );
  }
  return result;
}

function optionalCategory(value: unknown): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "support_category_invalid",
      "Support category is invalid.",
    );
  }
  const result = value.trim().toLowerCase();
  if (!/^[a-z0-9_-]{1,64}$/.test(result)) {
    throw new ApiError(
      400,
      "support_category_invalid",
      "Support category is invalid.",
    );
  }
  return result;
}

function optionalTimestamp(value: string | null): string | null {
  if (value == null || value === "") return null;
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new ApiError(400, "invalid_timestamp", "Timestamp is invalid.");
  }
  return date.toISOString();
}

function boundedLimit(value: string | null): number {
  if (value == null || value === "") return 50;
  if (!/^\d{1,3}$/.test(value)) {
    throw new ApiError(400, "invalid_page_size", "Page size is invalid.");
  }
  const limit = Number(value);
  if (limit < 1 || limit > 100) {
    throw new ApiError(400, "invalid_page_size", "Page size is invalid.");
  }
  return limit;
}
