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
