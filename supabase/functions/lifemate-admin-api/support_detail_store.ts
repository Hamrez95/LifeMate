import { type AdminSql, getAdminSql } from "./database_client.ts";
import {
  assertSupportTicketActionResult,
  type SupportTicketAction,
  type SupportTicketActionPayload,
  type SupportTicketEventsQuery,
} from "./support_detail.ts";
import type { SupportSlaState } from "./support.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

export type SupportTicketDetail = {
  ticketId: string;
  ticketNumber: number;
  requesterAccountId: string;
  requesterDisplayName: string | null;
  productCode: string | null;
  category: string;
  status: string;
  priority: string;
  summary: string | null;
  assignedAdminAccountId: string | null;
  assigneeDisplayName: string | null;
  slaState: SupportSlaState;
  nextDueAtUtc: string | null;
  lastActivityAtUtc: string;
  createdAtUtc: string;
};

export type SupportTicketEvent = {
  eventId: string;
  eventType: string;
  actorAccountId: string | null;
  actorDisplayName: string | null;
  summary: string | null;
  fromValue: string | null;
  toValue: string | null;
  occurredAtUtc: string;
};

export type SupportAssignee = {
  accountId: string;
  displayName: string | null;
};

function mapDetail(row: Record<string, unknown>): SupportTicketDetail {
  return {
    ticketId: String(row.ticket_id),
    ticketNumber: Number(row.ticket_number),
    requesterAccountId: String(row.requester_account_id),
    requesterDisplayName: nullableString(row.requester_display_name),
    productCode: nullableString(row.product_code),
    category: String(row.category),
    status: String(row.status),
    priority: String(row.priority),
    summary: nullableString(row.queue_summary_redacted),
    assignedAdminAccountId: nullableString(row.assigned_admin_account_id),
    assigneeDisplayName: nullableString(row.assignee_display_name),
    slaState: String(row.sla_state) as SupportSlaState,
    nextDueAtUtc: row.next_due_at_utc == null ? null : iso(row.next_due_at_utc),
    lastActivityAtUtc: iso(row.last_activity_at_utc),
    createdAtUtc: iso(row.created_at_utc),
  };
}

function mapEvent(row: Record<string, unknown>): SupportTicketEvent {
  return {
    eventId: String(row.event_id),
    eventType: String(row.event_type),
    actorAccountId: nullableString(row.actor_account_id),
    actorDisplayName: nullableString(row.actor_display_name),
    summary: nullableString(row.safe_summary),
    fromValue: nullableString(row.from_value),
    toValue: nullableString(row.to_value),
    occurredAtUtc: iso(row.occurred_at_utc),
  };
}

async function getSupportTicketDetail(sql: AdminSql, ticketId: string) {
  const rows = await sql`
    select ticket_id, ticket_number, requester_account_id, requester_display_name,
           product_code, category, status, priority, queue_summary_redacted,
           assigned_admin_account_id, assignee_display_name, sla_state,
           next_due_at_utc, last_activity_at_utc, created_at_utc
    from admin.support_ticket_queue_v1
    where ticket_id = ${ticketId}::uuid
    limit 1
  `;
  return rows.length === 0
    ? null
    : mapDetail(rows[0] as unknown as Record<string, unknown>);
}

async function listSupportTicketEvents(
  sql: AdminSql,
  ticketId: string,
  query: SupportTicketEventsQuery,
) {
  const countRows = await sql`
    select count(*)::integer as total
    from admin.support_ticket_events_v1
    where ticket_id = ${ticketId}::uuid
  `;
  const rows = await sql`
    select event_id, event_type, actor_account_id, actor_display_name,
           safe_summary, from_value, to_value, occurred_at_utc
    from admin.support_ticket_events_v1
    where ticket_id = ${ticketId}::uuid
    order by occurred_at_utc desc, event_id desc
    limit ${query.pageSize} offset ${query.offset}
  `;
  return {
    items: (rows as unknown as Record<string, unknown>[]).map(mapEvent),
    total: Number(countRows[0]?.total ?? 0),
  };
}

async function listSupportAssignees(sql: AdminSql) {
  const rows = await sql`
    select m.account_id,
           p.display_name
    from admin.members m
    left join core.account_person_links l
      on l.account_id = m.account_id
     and l.link_type = 'Self'
     and l.status = 'Active'
    left join core.person_profiles p on p.person_id = l.person_id
    where m.status = 'Active'
      and admin.account_has_permission(m.account_id, 'support.read')
    order by p.display_name nulls last, m.account_id asc
    limit 250
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    accountId: String(row.account_id),
    displayName: nullableString(row.display_name),
  }));
}

export function createSupportTicketDetailStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    getDetail: (ticketId: string) => getSupportTicketDetail(sql, ticketId),
    listEvents: (ticketId: string, query: SupportTicketEventsQuery) =>
      listSupportTicketEvents(sql, ticketId, query),
    listAssignees: () => listSupportAssignees(sql),
    async execute(input: {
      actorAccountId: string;
      ticketId: string;
      action: SupportTicketAction;
      payload: SupportTicketActionPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.execute_support_ticket_action(
          ${input.actorAccountId}::uuid,
          ${input.ticketId}::uuid,
          ${input.action}::character varying,
          ${JSON.stringify(input.payload)}::jsonb,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return assertSupportTicketActionResult(rows[0]?.result);
    },
  };
}
