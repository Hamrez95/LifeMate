import { json } from "./http.ts";
import { enforceRateLimit } from "./security.ts";
import {
  type createSupportAttachmentRuntime,
  supportAttachmentMaximumBytes,
} from "./support_attachment_storage.ts";
import { ApiError, readJsonObject } from "./validation.ts";
import type { createSupportConversationStore } from "./support_conversations.ts";

type Store = ReturnType<typeof createSupportConversationStore>;
type AttachmentRuntime = ReturnType<typeof createSupportAttachmentRuntime>;

export function createSupportConversationRouteHandler(
  store: Store,
  attachments?: AttachmentRuntime,
) {
  return async (input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> => {
    const { request, path, appUserId } = input;

    if (
      request.method === "GET" &&
      path === "/api/v1/support/conversations/current"
    ) {
      const url = new URL(request.url);
      const productCode = optionalProductCode(
        url.searchParams.get("productCode"),
      );
      const category = optionalCategory(url.searchParams.get("category")) ??
        "general";
      return json({
        conversation: await store.current(appUserId, productCode, category),
      });
    }

    if (request.method === "POST" && path === "/api/v1/support/conversations") {
      enforceRateLimit(`support-open:${appUserId}`, 5, 24 * 60 * 60_000);
      const body = await readJsonObject(request);
      return json(
        await store.open(appUserId, {
          productCode: optionalProductCode(body.productCode),
          category: optionalCategory(body.category) ?? "general",
          body: requiredMessage(body.body),
          clientMessageId: requiredUuid(body.clientMessageId),
        }),
        201,
      );
    }

    const attachmentUpload = path.match(
      /^\/api\/v1\/support\/conversations\/([0-9a-f-]{36})\/messages\/([0-9a-f-]{36})\/attachments$/i,
    );
    if (request.method === "PUT" && attachmentUpload) {
      if (!attachments) throw attachmentRuntimeUnavailable();
      enforceRateLimit(`support-attachment:${appUserId}`, 20, 60 * 60_000);
      const ticketId = requiredUuid(attachmentUpload[1]);
      const messageId = requiredUuid(attachmentUpload[2]);
      const fileName = requiredFileName(request.headers.get("x-file-name"));
      const declaredLength = Number(request.headers.get("content-length") ?? 0);
      if (
        Number.isFinite(declaredLength) &&
        declaredLength > supportAttachmentMaximumBytes
      ) {
        throw new ApiError(
          413,
          "support_attachment_too_large",
          "Attachment must be no larger than 10 MB.",
        );
      }
      const bytes = new Uint8Array(await request.arrayBuffer());
      const contentType = request.headers.get("content-type") ?? "";
      const accountId = await store.accountIdForAppUser(appUserId);
      const uploaded = await attachments.upload(
        accountId,
        ticketId,
        messageId,
        bytes,
        contentType,
      );
      const sha256 = await sha256Hex(bytes);
      let registered: Record<string, unknown>;
      try {
        registered = await store.registerAttachment(appUserId, {
          ticketId,
          messageId,
          fileName,
          contentType: uploaded.contentType,
          sizeBytes: bytes.byteLength,
          objectPath: uploaded.objectPath,
          sha256,
        });
      } catch (error) {
        await attachments.remove(uploaded.objectPath).catch(() => undefined);
        throw error;
      }
      const attachmentId = requiredResultUuid(registered.attachmentId);
      const scan = await attachments.scan(
        bytes,
        uploaded.contentType,
        fileName,
      );
      const finalized = await store.finalizeAttachmentScan(
        appUserId,
        attachmentId,
        scan.status,
        scan.reasonCode,
      );
      // There is no durable rescan queue in this source slice. Retaining an
      // untrusted object after malware rejection *or* scanner failure would keep
      // user content without a usable lifecycle. Preserve the database status for
      // audit/UX, but remove the Storage object unless the scanner explicitly
      // marked it clean. A retry uploads a fresh object and runs a fresh scan.
      if (scan.status !== "Available") {
        await attachments.remove(uploaded.objectPath).catch(() => undefined);
      }
      return json({
        attachmentId,
        messageId,
        scanStatus: String(finalized.scanStatus ?? scan.status),
        downloadable: scan.status === "Available",
      }, scan.status === "Available" ? 201 : 202);
    }

    const attachmentDownload = path.match(
      /^\/api\/v1\/support\/conversations\/([0-9a-f-]{36})\/attachments\/([0-9a-f-]{36})\/download$/i,
    );
    if (request.method === "GET" && attachmentDownload) {
      if (!attachments) throw attachmentRuntimeUnavailable();
      enforceRateLimit(
        `support-attachment-download:${appUserId}`,
        60,
        60 * 60_000,
      );
      const ticketId = requiredUuid(attachmentDownload[1]);
      const attachmentId = requiredUuid(attachmentDownload[2]);
      const available = await store.getAttachmentDownload(
        appUserId,
        ticketId,
        attachmentId,
      );
      return json({
        attachmentId: available.attachmentId,
        fileName: available.fileName,
        contentType: available.contentType,
        sizeBytes: available.sizeBytes,
        signedUrl: await attachments.signedDownload(available.objectPath),
        expiresInSeconds: 600,
      });
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
      const afterAt = optionalTimestamp(url.searchParams.get("afterAt"));
      if (beforeAt && afterAt) {
        throw new ApiError(
          400,
          "support_cursor_conflict",
          "Use either beforeAt or afterAt, not both.",
        );
      }
      const limit = boundedLimit(url.searchParams.get("limit"));
      const items = await store.list(
        appUserId,
        ticketId,
        beforeAt,
        afterAt,
        limit,
      );
      return json({
        items,
        polling: {
          afterAt: items.length === 0 ? afterAt : items[0].createdAtUtc,
        },
      });
    }

    if (request.method === "POST" && suffix === "messages") {
      enforceRateLimit(`support-send:${appUserId}`, 60, 60 * 60_000);
      const body = await readJsonObject(request);
      return json(
        await store.send(appUserId, ticketId, {
          body: requiredMessage(body.body),
          clientMessageId: requiredUuid(body.clientMessageId),
        }),
        201,
      );
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
      .test(
        value,
      )
  ) {
    throw new ApiError(400, "invalid_uuid", "Identifier is invalid.");
  }
  return value.toLowerCase();
}

function requiredResultUuid(value: unknown): string {
  if (typeof value !== "string") {
    throw new Error("support_attachment_result_invalid");
  }
  return requiredUuid(value);
}

function requiredMessage(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "support_message_invalid", "Message is invalid.");
  }
  const text = value.trim();
  if (
    !text ||
    text.length > 4000 ||
    new TextEncoder().encode(text).byteLength > 12000
  ) {
    throw new ApiError(400, "support_message_invalid", "Message is invalid.");
  }
  return text;
}

function requiredFileName(value: string | null): string {
  const fileName = value?.trim() ?? "";
  if (
    !fileName ||
    fileName.length > 180 ||
    /[\\/\u0000-\u001f]/.test(fileName)
  ) {
    throw new ApiError(
      400,
      "support_attachment_name_invalid",
      "Attachment file name is invalid.",
    );
  }
  return fileName;
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
    !result ||
    result.length > 64 ||
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

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    Uint8Array.from(bytes).buffer,
  );
  return Array.from(new Uint8Array(digest)).map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

function attachmentRuntimeUnavailable(): ApiError {
  return new ApiError(
    503,
    "support_attachment_runtime_unavailable",
    "Attachment service is temporarily unavailable.",
  );
}
