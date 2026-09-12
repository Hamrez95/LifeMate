import { type AdminSql, getAdminSql } from "./database_client.ts";

type Row = Record<string, unknown>;

export type AdminSupportConversationMessage = {
  messageId: string;
  ticketId: string;
  senderKind: "User" | "Staff";
  senderAccountId: string;
  senderDisplayName: string | null;
  body: string;
  createdAtUtc: string;
};

export function createSupportConversationAdminStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    list: (
      ticketId: string,
      beforeAt: string | null,
      afterAt: string | null,
      limit: number,
    ) => listMessages(sql, ticketId, beforeAt, afterAt, limit),
    async send(input: {
      actorAccountId: string;
      ticketId: string;
      body: string;
      clientMessageId: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.send_support_conversation_message(
          ${input.actorAccountId}::uuid,
          ${input.ticketId}::uuid,
          ${input.body}::text,
          ${input.clientMessageId}::uuid,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return requiredResult(rows[0]?.result, "support_conversation_send_result_invalid");
    },
    async escalate(input: {
      actorAccountId: string;
      ticketId: string;
      targetRoleCode: string;
      safeReason: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.create_support_escalation_idempotent(
          ${input.actorAccountId}::uuid,
          ${input.ticketId}::uuid,
          ${input.targetRoleCode}::varchar,
          ${input.safeReason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return requiredResult(rows[0]?.result, "support_escalation_result_invalid");
    },
    async linkReference(input: {
      actorAccountId: string;
      ticketId: string;
      linkKind: string;
      referenceCode: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.link_support_ticket_reference_idempotent(
          ${input.actorAccountId}::uuid,
          ${input.ticketId}::uuid,
          ${input.linkKind}::varchar,
          ${input.referenceCode}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return requiredResult(rows[0]?.result, "support_reference_result_invalid");
    },
    async listOperations(ticketId: string) {
      const escalations = await sql`
        select e.id as escalation_id,e.status,e.safe_reason,e.created_at_utc,
               r.code as target_role_code,r.display_name as target_role_name
        from support.ticket_escalations e
        join admin.roles r on r.id=e.target_role_id
        where e.ticket_id=${ticketId}::uuid
        order by e.created_at_utc desc,e.id desc
        limit 100
      `;
      const links = await sql`
        select id as link_id,link_kind,reference_code,created_at_utc
        from support.ticket_links
        where ticket_id=${ticketId}::uuid
        order by created_at_utc desc,id desc
        limit 100
      `;
      return {
        escalations: (escalations as unknown as Row[]).map(mapEscalation),
        links: (links as unknown as Row[]).map(mapLink),
      };
    },
  };
}

async function listMessages(
  sql: AdminSql,
  ticketId: string,
  beforeAt: string | null,
  afterAt: string | null,
  limit: number,
): Promise<AdminSupportConversationMessage[]> {
  const rows = await sql`
    select message_id,ticket_id,sender_kind,sender_account_id,
           sender_display_name,body,created_at_utc
    from admin.support_conversation_messages_v1
    where ticket_id=${ticketId}::uuid
      and (${beforeAt}::timestamptz is null or created_at_utc < ${beforeAt}::timestamptz)
      and (${afterAt}::timestamptz is null or created_at_utc > ${afterAt}::timestamptz)
    order by created_at_utc desc,message_id desc
    limit ${limit}
  `;
  return (rows as unknown as Row[]).map(mapMessage);
}

function requiredResult(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(code);
  }
  return value as Record<string, unknown>;
}

function mapMessage(row: Row): AdminSupportConversationMessage {
  const senderKind = row.sender_kind;
  if (senderKind !== "User" && senderKind !== "Staff") {
    throw new Error("support_sender_kind_invalid");
  }
  return {
    messageId: String(row.message_id),
    ticketId: String(row.ticket_id),
    senderKind,
    senderAccountId: String(row.sender_account_id),
    senderDisplayName: typeof row.sender_display_name === "string"
      ? row.sender_display_name
      : null,
    body: String(row.body),
    createdAtUtc: row.created_at_utc instanceof Date
      ? row.created_at_utc.toISOString()
      : String(row.created_at_utc),
  };
}

function mapEscalation(row: Row) {
  return {
    escalationId: String(row.escalation_id),
    status: String(row.status),
    safeReason: String(row.safe_reason),
    targetRoleCode: String(row.target_role_code),
    targetRoleName: String(row.target_role_name),
    createdAtUtc: row.created_at_utc instanceof Date
      ? row.created_at_utc.toISOString()
      : String(row.created_at_utc),
  };
}

function mapLink(row: Row) {
  return {
    linkId: String(row.link_id),
    linkKind: String(row.link_kind),
    referenceCode: String(row.reference_code),
    createdAtUtc: row.created_at_utc instanceof Date
      ? row.created_at_utc.toISOString()
      : String(row.created_at_utc),
  };
}
