import type { AdminSql } from "./database_client.ts";
import type {
  SupportQueueQuery,
  SupportSlaState,
  SupportTicketPriority,
  SupportTicketStatus,
} from "./support.ts";

type Row = Record<string, unknown>;

export type SupportTicketQueueItem = {
  ticketId: string;
  ticketNumber: number;
  requesterAccountId: string;
  requesterDisplayName: string | null;
  productCode: string | null;
  category: string;
  status: SupportTicketStatus;
  priority: SupportTicketPriority;
  summary: string | null;
  assignedAdminAccountId: string | null;
  assigneeDisplayName: string | null;
  slaState: SupportSlaState;
  nextDueAtUtc: string | null;
  lastActivityAtUtc: string;
  createdAtUtc: string;
};

export type SupportQueueResult = {
  items: SupportTicketQueueItem[];
  total: number;
};

function asIso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function asNullableIso(value: unknown): string | null {
  return value == null ? null : asIso(value);
}

function asNullableString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function mapItem(row: Row): SupportTicketQueueItem {
  return {
    ticketId: String(row.ticket_id),
    ticketNumber: Number(row.ticket_number),
    requesterAccountId: String(row.requester_account_id),
    requesterDisplayName: asNullableString(row.requester_display_name),
    productCode: asNullableString(row.product_code),
    category: String(row.category),
    status: String(row.status) as SupportTicketStatus,
    priority: String(row.priority) as SupportTicketPriority,
    summary: asNullableString(row.queue_summary_redacted),
    assignedAdminAccountId: asNullableString(row.assigned_admin_account_id),
    assigneeDisplayName: asNullableString(row.assignee_display_name),
    slaState: String(row.sla_state) as SupportSlaState,
    nextDueAtUtc: asNullableIso(row.next_due_at_utc),
    lastActivityAtUtc: asIso(row.last_activity_at_utc),
    createdAtUtc: asIso(row.created_at_utc),
  };
}

export async function listSupportQueue(
  sql: AdminSql,
  query: SupportQueueQuery,
): Promise<SupportQueueResult> {
  const numericTicket = query.search && /^#?\d{1,18}$/.test(query.search)
    ? Number(query.search.replace(/^#/, ""))
    : null;

  const countRows = await sql`
    select count(*)::integer as total
    from admin.support_ticket_queue_v1
    where (${query.status}::text is null or status = ${query.status}::varchar)
      and (${query.priority}::text is null or priority = ${query.priority}::varchar)
      and (${query.product}::text is null or lower(product_code) = ${query.product}::text)
      and (${query.sla}::text is null or sla_state = ${query.sla}::text)
      and (
        ${query.assigneeAccountId}::uuid is null
        or assigned_admin_account_id = ${query.assigneeAccountId}::uuid
      )
      and (not ${query.unassignedOnly}::boolean or assigned_admin_account_id is null)
      and (
        ${query.search}::text is null
        or (${numericTicket}::bigint is not null and ticket_number = ${numericTicket}::bigint)
        or strpos(lower(coalesce(requester_display_name, '')), lower(${query.search}::text)) > 0
        or strpos(lower(coalesce(queue_summary_redacted, '')), lower(${query.search}::text)) > 0
      )
  `;

  const rows = await sql`
    select ticket_id, ticket_number, requester_account_id, requester_display_name,
           product_code, category, status, priority, queue_summary_redacted,
           assigned_admin_account_id, assignee_display_name, sla_state,
           next_due_at_utc, last_activity_at_utc, created_at_utc
    from admin.support_ticket_queue_v1
    where (${query.status}::text is null or status = ${query.status}::varchar)
      and (${query.priority}::text is null or priority = ${query.priority}::varchar)
      and (${query.product}::text is null or lower(product_code) = ${query.product}::text)
      and (${query.sla}::text is null or sla_state = ${query.sla}::text)
      and (
        ${query.assigneeAccountId}::uuid is null
        or assigned_admin_account_id = ${query.assigneeAccountId}::uuid
      )
      and (not ${query.unassignedOnly}::boolean or assigned_admin_account_id is null)
      and (
        ${query.search}::text is null
        or (${numericTicket}::bigint is not null and ticket_number = ${numericTicket}::bigint)
        or strpos(lower(coalesce(requester_display_name, '')), lower(${query.search}::text)) > 0
        or strpos(lower(coalesce(queue_summary_redacted, '')), lower(${query.search}::text)) > 0
      )
    order by
      case priority
        when 'Urgent' then 4
        when 'High' then 3
        when 'Normal' then 2
        else 1
      end desc,
      case sla_state
        when 'Breached' then 4
        when 'DueSoon' then 3
        when 'OnTrack' then 2
        else 1
      end desc,
      last_activity_at_utc desc,
      ticket_id asc
    limit ${query.pageSize}
    offset ${query.offset}
  `;

  return {
    total: Number(countRows[0]?.total ?? 0),
    items: (rows as unknown as Row[]).map(mapItem),
  };
}
