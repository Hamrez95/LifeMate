import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export type SupportConversationMessage = {
  messageId: string;
  senderKind: "User" | "Staff";
  body: string;
  createdAtUtc: string;
};

export function createSupportConversationStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function accountIdForAppUser(appUserId: string): Promise<string> {
    const rows = await sql`
      select identity.account_id_for_legacy_app_user(${appUserId}::uuid) as account_id
    `;
    const accountId = rows[0]?.account_id;
    if (typeof accountId !== "string") {
      throw new ApiError(
        404,
        "support_account_unavailable",
        "Support account mapping is unavailable.",
      );
    }
    return accountId;
  }

  return {
    accountIdForAppUser,

    async current(
      appUserId: string,
      productCode: string | null,
      category: string,
    ) {
      const accountId = await accountIdForAppUser(appUserId);
      const rows = await sql`
        select * from support.get_latest_user_support_conversation(
          ${accountId}::uuid,
          ${productCode}::varchar,
          ${category}::varchar
        )
      `;
      const row = rows[0] as Row | undefined;
      if (!row) return null;
      return {
        ticketId: String(row.ticket_id),
        status: String(row.status),
        productCode: row.product_code == null ? null : String(row.product_code),
        lastActivityAtUtc: row.last_activity_at_utc instanceof Date
          ? row.last_activity_at_utc.toISOString()
          : String(row.last_activity_at_utc),
      };
    },

    async open(appUserId: string, input: {
      productCode: string | null;
      category: string;
      body: string;
      clientMessageId: string;
    }) {
      const accountId = await accountIdForAppUser(appUserId);
      const rows = await sql`
        select support.open_support_conversation(
          ${accountId}::uuid,
          ${input.productCode}::varchar,
          ${input.category}::varchar,
          ${input.body}::text,
          ${input.clientMessageId}::uuid
        ) as result
      `;
      return requiredResult(rows[0]?.result);
    },

    async send(appUserId: string, ticketId: string, input: {
      body: string;
      clientMessageId: string;
    }) {
      const accountId = await accountIdForAppUser(appUserId);
      const rows = await sql`
        select support.send_user_support_message(
          ${accountId}::uuid,
          ${ticketId}::uuid,
          ${input.body}::text,
          ${input.clientMessageId}::uuid
        ) as result
      `;
      return requiredResult(rows[0]?.result);
    },

    async list(
      appUserId: string,
      ticketId: string,
      beforeAt: string | null,
      afterAt: string | null,
      limit: number,
    ) {
      const accountId = await accountIdForAppUser(appUserId);
      const rows = await sql`
        select * from support.list_user_support_messages_v2(
          ${accountId}::uuid,
          ${ticketId}::uuid,
          ${beforeAt}::timestamptz,
          ${afterAt}::timestamptz,
          ${limit}::integer
        )
      `;
      return (rows as unknown as Row[]).map(mapMessage);
    },

    async markRead(appUserId: string, ticketId: string, messageId: string) {
      const accountId = await accountIdForAppUser(appUserId);
      const rows = await sql`
        select support.mark_user_support_read(
          ${accountId}::uuid,
          ${ticketId}::uuid,
          ${messageId}::uuid
        ) as ok
      `;
      if (rows[0]?.ok !== true) {
        throw new ApiError(
          404,
          "support_message_not_found",
          "Support message was not found.",
        );
      }
      return { ok: true };
    },

    async registerAttachment(appUserId: string, input: {
      ticketId: string;
      messageId: string;
      fileName: string;
      contentType: string;
      sizeBytes: number;
      objectPath: string;
      sha256: string;
    }) {
      const accountId = await accountIdForAppUser(appUserId);
      const rows = await sql`
        select support.register_user_support_attachment(
          ${accountId}::uuid,
          ${input.ticketId}::uuid,
          ${input.messageId}::uuid,
          ${input.fileName}::varchar,
          ${input.contentType}::varchar,
          ${input.sizeBytes}::bigint,
          ${input.objectPath}::varchar,
          ${input.sha256}::char(64)
        ) as result
      `;
      return { accountId, ...requiredResult(rows[0]?.result) };
    },

    async finalizeAttachmentScan(
      appUserId: string,
      attachmentId: string,
      status: "Available" | "Rejected" | "ScanError",
      reasonCode: string | null,
    ) {
      const accountId = await accountIdForAppUser(appUserId);
      const rows = await sql`
        select support.finalize_user_support_attachment_scan(
          ${accountId}::uuid,
          ${attachmentId}::uuid,
          ${status}::varchar,
          ${reasonCode}::varchar
        ) as result
      `;
      return requiredResult(rows[0]?.result);
    },

    async getAttachmentDownload(
      appUserId: string,
      ticketId: string,
      attachmentId: string,
    ) {
      const accountId = await accountIdForAppUser(appUserId);
      const rows = await sql`
        select * from support.get_user_support_attachment_download(
          ${accountId}::uuid,
          ${ticketId}::uuid,
          ${attachmentId}::uuid
        )
      `;
      const row = rows[0] as Row | undefined;
      if (!row) {
        throw new ApiError(
          404,
          "support_attachment_unavailable",
          "Attachment is unavailable.",
        );
      }
      return {
        attachmentId: String(row.attachment_id),
        objectPath: String(row.storage_object_path),
        fileName: String(row.original_file_name),
        contentType: String(row.content_type),
        sizeBytes: Number(row.size_bytes),
      };
    },
  };
}

function requiredResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("support_conversation_result_invalid");
  }
  return value as Record<string, unknown>;
}

function mapMessage(row: Row): SupportConversationMessage {
  const senderKind = row.sender_kind;
  if (senderKind !== "User" && senderKind !== "Staff") {
    throw new Error("support_sender_kind_invalid");
  }
  return {
    messageId: String(row.message_id),
    senderKind,
    body: String(row.body),
    createdAtUtc: row.created_at_utc instanceof Date
      ? row.created_at_utc.toISOString()
      : String(row.created_at_utc),
  };
}
