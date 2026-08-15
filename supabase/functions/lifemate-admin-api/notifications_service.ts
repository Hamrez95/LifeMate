import { type AdminSql, getAdminSql } from "./database_client.ts";
import { safeError } from "./http.ts";
import {
  assertNotificationReadStateResult,
  assertSafeNotificationDeepLink,
  type NotificationQuery,
  type NotificationReadStateRequest,
  type NotificationSeverity,
  type NotificationSource,
} from "./notifications.ts";

export type NotificationAlert = {
  alertKey: string;
  source: NotificationSource;
  severity: NotificationSeverity;
  title: string;
  summary: string | null;
  occurredAtUtc: string;
  freshnessAtUtc: string;
  isRead: boolean;
  deepLink: string | null;
  canMarkRead: true;
  canAcknowledge: false;
  canDismiss: false;
};

export type NotificationSourceState = {
  source: NotificationSource;
  state: "ready" | "empty" | "unavailable" | "not_instrumented";
  total: number | null;
  unreadCount: number | null;
  asOfUtc: string;
  reasonCode: string | null;
};

type LoadedSource = {
  state: NotificationSourceState;
  items: NotificationAlert[];
  filteredTotal: number | null;
};

export type NotificationCenterResult = {
  items: NotificationAlert[];
  page: number;
  pageSize: number;
  knownTotal: number;
  total: number | null;
  knownUnreadCount: number;
  unreadCount: number | null;
  completeness: "complete" | "partial";
  sourceStates: NotificationSourceState[];
  asOfUtc: string;
};

type Row = Record<string, unknown>;

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function nullableIso(value: unknown): string | null {
  return value == null ? null : iso(value);
}

function numberValue(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function readState(readAt: unknown, eventAt: unknown): boolean {
  if (readAt == null || eventAt == null) return false;
  const read = new Date(iso(readAt)).getTime();
  const event = new Date(iso(eventAt)).getTime();
  return Number.isFinite(read) && Number.isFinite(event) && read >= event;
}

function sourceState(
  source: NotificationSource,
  total: number,
  unreadCount: number,
  asOfUtc: string,
): NotificationSourceState {
  return {
    source,
    state: total === 0 ? "empty" : "ready",
    total,
    unreadCount,
    asOfUtc,
    reasonCode: null,
  };
}

function unavailableState(
  source: NotificationSource,
  reasonCode = "source_unavailable",
): LoadedSource {
  return {
    items: [],
    filteredTotal: null,
    state: {
      source,
      state: "unavailable",
      total: null,
      unreadCount: null,
      asOfUtc: new Date().toISOString(),
      reasonCode,
    },
  };
}

function notInstrumented(source: NotificationSource): LoadedSource {
  return {
    items: [],
    filteredTotal: null,
    state: {
      source,
      state: "not_instrumented",
      total: null,
      unreadCount: null,
      asOfUtc: new Date().toISOString(),
      reasonCode: "canonical_source_not_instrumented",
    },
  };
}

async function loadSupport(
  sql: AdminSql,
  accountId: string,
  limit: number,
  unreadOnly: boolean,
): Promise<LoadedSource> {
  const countRows = await sql`
    with alerts as (
      select q.ticket_id,
             'support:ticket:' || q.ticket_id::text || ':sla' as alert_key,
             case
               when q.sla_state='Breached' and q.next_due_at_utc is not null
                 then q.next_due_at_utc
               when q.sla_state='DueSoon' and q.next_due_at_utc is not null
                 then q.next_due_at_utc - interval '2 hours'
               else q.last_activity_at_utc
             end as event_at_utc
      from admin.support_ticket_queue_v1 q
      where q.status not in ('Resolved','Closed')
        and (q.sla_state in ('Breached','DueSoon') or q.priority='Urgent')
    ), annotated as (
      select a.*,
             r.read_at_utc,
             coalesce(r.read_at_utc >= a.event_at_utc, false) as is_read
      from alerts a
      left join admin.notification_read_receipts r
        on r.actor_account_id=${accountId}::uuid
       and r.alert_key=a.alert_key
    )
    select count(*)::integer as active_total,
           count(*) filter (where not is_read)::integer as unread_count
    from annotated
  `;
  const activeTotal = numberValue(countRows[0]?.active_total);
  const unreadCount = numberValue(countRows[0]?.unread_count);

  const rows = await sql`
    with alerts as (
      select q.ticket_id, q.ticket_number, q.priority, q.sla_state,
             q.queue_summary_redacted,
             q.updated_at_utc,
             'support:ticket:' || q.ticket_id::text || ':sla' as alert_key,
             case
               when q.sla_state='Breached' and q.next_due_at_utc is not null
                 then q.next_due_at_utc
               when q.sla_state='DueSoon' and q.next_due_at_utc is not null
                 then q.next_due_at_utc - interval '2 hours'
               else q.last_activity_at_utc
             end as event_at_utc
      from admin.support_ticket_queue_v1 q
      where q.status not in ('Resolved','Closed')
        and (q.sla_state in ('Breached','DueSoon') or q.priority='Urgent')
    ), annotated as (
      select a.*,
             r.read_at_utc,
             coalesce(r.read_at_utc >= a.event_at_utc, false) as is_read
      from alerts a
      left join admin.notification_read_receipts r
        on r.actor_account_id=${accountId}::uuid
       and r.alert_key=a.alert_key
    )
    select * from annotated
    where (not ${unreadOnly}::boolean or not is_read)
    order by event_at_utc desc, ticket_id asc
    limit ${limit}
  `;

  const items = (rows as unknown as Row[]).map((row): NotificationAlert => {
    const breached = String(row.sla_state) === "Breached";
    const urgent = String(row.priority) === "Urgent";
    const severity: NotificationSeverity = breached || urgent
      ? "critical"
      : "warning";
    const ticketNumber = String(row.ticket_number);
    const title = breached
      ? `SLA تیکت #${ticketNumber} نقض شده است`
      : String(row.sla_state) === "DueSoon"
      ? `SLA تیکت #${ticketNumber} نزدیک است`
      : `تیکت فوری #${ticketNumber} نیاز به توجه دارد`;
    return {
      alertKey: String(row.alert_key),
      source: "support",
      severity,
      title,
      summary: typeof row.queue_summary_redacted === "string"
        ? row.queue_summary_redacted
        : null,
      occurredAtUtc: iso(row.event_at_utc),
      freshnessAtUtc: iso(row.updated_at_utc),
      isRead: Boolean(row.is_read),
      deepLink: assertSafeNotificationDeepLink(
        "support",
        `/support/${String(row.ticket_id)}`,
      ),
      canMarkRead: true,
      canAcknowledge: false,
      canDismiss: false,
    };
  });

  return {
    items,
    filteredTotal: unreadOnly ? unreadCount : activeTotal,
    state: sourceState(
      "support",
      activeTotal,
      unreadCount,
      new Date().toISOString(),
    ),
  };
}

async function loadSecurity(
  sql: AdminSql,
  accountId: string,
  limit: number,
  unreadOnly: boolean,
): Promise<LoadedSource> {
  const countRows = await sql`
    with alerts as (
      select e.id,
             'security:audit:' || e.id::text as alert_key,
             e.occurred_at_utc as event_at_utc
      from admin.audit_events e
      where e.occurred_at_utc >= now() - interval '7 days'
        and (e.result='Failed' or (e.result='Denied' and e.elevated_access=true))
    ), annotated as (
      select a.*,
             r.read_at_utc,
             coalesce(r.read_at_utc >= a.event_at_utc, false) as is_read
      from alerts a
      left join admin.notification_read_receipts r
        on r.actor_account_id=${accountId}::uuid
       and r.alert_key=a.alert_key
    )
    select count(*)::integer as active_total,
           count(*) filter (where not is_read)::integer as unread_count
    from annotated
  `;
  const activeTotal = numberValue(countRows[0]?.active_total);
  const unreadCount = numberValue(countRows[0]?.unread_count);

  const rows = await sql`
    with alerts as (
      select e.id, e.action, e.resource_type, e.result, e.elevated_access,
             e.occurred_at_utc,
             'security:audit:' || e.id::text as alert_key
      from admin.audit_events e
      where e.occurred_at_utc >= now() - interval '7 days'
        and (e.result='Failed' or (e.result='Denied' and e.elevated_access=true))
    ), annotated as (
      select a.*,
             r.read_at_utc,
             coalesce(r.read_at_utc >= a.occurred_at_utc, false) as is_read
      from alerts a
      left join admin.notification_read_receipts r
        on r.actor_account_id=${accountId}::uuid
       and r.alert_key=a.alert_key
    )
    select * from annotated
    where (not ${unreadOnly}::boolean or not is_read)
    order by occurred_at_utc desc, id asc
    limit ${limit}
  `;

  const items = (rows as unknown as Row[]).map((row): NotificationAlert => {
    const elevated = row.elevated_access === true;
    return {
      alertKey: String(row.alert_key),
      source: "security",
      severity: elevated ? "critical" : "warning",
      title: elevated
        ? "دسترسی حساس ناموفق یا رد شده است"
        : "یک عملیات مدیریتی ناموفق بوده است",
      summary: `${String(row.action)} · ${String(row.resource_type)}`,
      occurredAtUtc: iso(row.occurred_at_utc),
      freshnessAtUtc: iso(row.occurred_at_utc),
      isRead: Boolean(row.is_read),
      deepLink: assertSafeNotificationDeepLink("security", "/security"),
      canMarkRead: true,
      canAcknowledge: false,
      canDismiss: false,
    };
  });

  return {
    items,
    filteredTotal: unreadOnly ? unreadCount : activeTotal,
    state: sourceState(
      "security",
      activeTotal,
      unreadCount,
      new Date().toISOString(),
    ),
  };
}

function receiptMap(rows: readonly Row[]): Map<string, string> {
  const result = new Map<string, string>();
  for (const row of rows) {
    if (typeof row.alert_key === "string" && row.read_at_utc != null) {
      result.set(row.alert_key, iso(row.read_at_utc));
    }
  }
  return result;
}

function shiftedIso(baseIso: string, seconds: number): string {
  return new Date(new Date(baseIso).getTime() + seconds * 1000).toISOString();
}

async function loadOperations(
  sql: AdminSql,
  accountId: string,
  unreadOnly: boolean,
): Promise<LoadedSource> {
  const [snapshotRows, receiptRows] = await Promise.all([
    sql`select * from admin.notification_operations_queue_snapshot()`,
    sql`
      select alert_key, read_at_utc
      from admin.notification_read_receipts
      where actor_account_id=${accountId}::uuid
        and source_domain='operations'
    `,
  ]);
  const row = (snapshotRows[0] ?? {}) as Row;
  const receipts = receiptMap(receiptRows as unknown as Row[]);
  const measuredAt = iso(row.measured_at_utc ?? new Date());
  const alerts: NotificationAlert[] = [];

  const push = (
    alertKey: string,
    severity: NotificationSeverity,
    title: string,
    summary: string,
    occurredAtUtc: string,
  ) => {
    const readAt = receipts.get(alertKey);
    alerts.push({
      alertKey,
      source: "operations",
      severity,
      title,
      summary,
      occurredAtUtc,
      freshnessAtUtc: measuredAt,
      isRead: readState(readAt, occurredAtUtc),
      deepLink: assertSafeNotificationDeepLink("operations", "/operations"),
      canMarkRead: true,
      canAcknowledge: false,
      canDismiss: false,
    });
  };

  const deadLetters = numberValue(row.dead_letter_count);
  const latestDead = nullableIso(row.latest_dead_lettered_at_utc);
  if (deadLetters > 0 && latestDead) {
    push(
      "operations:outbox:dead-letter",
      "critical",
      "پیام‌های DeadLetter در صف Outbox وجود دارد",
      `${deadLetters} پیام نیاز به بررسی عملیاتی دارد؛ payload در Command Center نمایش داده نمی‌شود.`,
      latestDead,
    );
  }

  const oldestAge = numberValue(row.oldest_ready_age_seconds);
  if (oldestAge >= 120) {
    const critical = oldestAge >= 900;
    const eventAt = shiftedIso(measuredAt, -oldestAge);
    push(
      critical
        ? "operations:outbox:lag-critical"
        : "operations:outbox:lag-warning",
      critical ? "critical" : "warning",
      critical ? "تاخیر Outbox بحرانی است" : "تاخیر Outbox نیاز به توجه دارد",
      `قدیمی‌ترین پیام آماده حدود ${oldestAge} ثانیه در صف مانده است.`,
      eventAt,
    );
  }

  const stale = numberValue(row.stale_processing_count);
  const latestStaleLock = nullableIso(row.latest_stale_lock_at_utc);
  if (stale > 0 && latestStaleLock) {
    push(
      "operations:outbox:stale-lock",
      "warning",
      "قفل‌های قدیمی Worker مشاهده شده است",
      `${stale} پیام Processing بیش از ۱۰ دقیقه قفل مانده است.`,
      shiftedIso(latestStaleLock, 600),
    );
  }

  alerts.sort((a, b) => b.occurredAtUtc.localeCompare(a.occurredAtUtc));
  const unreadCount = alerts.filter((item) => !item.isRead).length;
  return {
    items: unreadOnly ? alerts.filter((item) => !item.isRead) : alerts,
    filteredTotal: unreadOnly ? unreadCount : alerts.length,
    state: sourceState("operations", alerts.length, unreadCount, measuredAt),
  };
}

async function loadSource(
  sql: AdminSql,
  accountId: string,
  source: NotificationSource,
  limit: number,
  unreadOnly: boolean,
  correlationId: string,
): Promise<LoadedSource> {
  if (source === "finance" || source === "product") {
    return notInstrumented(source);
  }
  try {
    if (source === "support") {
      return await loadSupport(sql, accountId, limit, unreadOnly);
    }
    if (source === "security") {
      return await loadSecurity(sql, accountId, limit, unreadOnly);
    }
    return await loadOperations(sql, accountId, unreadOnly);
  } catch (error) {
    console.warn("LifeMate Admin notification source unavailable", {
      correlationId,
      source,
      ...safeError(error),
    });
    return unavailableState(source);
  }
}

function severityRank(value: NotificationSeverity): number {
  return value === "critical" ? 3 : value === "warning" ? 2 : 1;
}

async function listNotifications(
  sql: AdminSql,
  accountId: string,
  query: NotificationQuery,
  authorizedSources: NotificationSource[],
  correlationId: string,
): Promise<NotificationCenterResult> {
  const offset = (query.page - 1) * query.pageSize;
  const perSourceLimit = Math.min(offset + query.pageSize, 250);
  const loaded = await Promise.all(
    authorizedSources.map((source) =>
      loadSource(
        sql,
        accountId,
        source,
        perSourceLimit,
        query.unreadOnly,
        correlationId,
      )
    ),
  );

  const merged = loaded.flatMap((source) => source.items).sort((a, b) => {
    const time = b.occurredAtUtc.localeCompare(a.occurredAtUtc);
    return time !== 0
      ? time
      : severityRank(b.severity) - severityRank(a.severity);
  });

  const knownTotal = loaded.reduce(
    (sum, source) => sum + (source.filteredTotal ?? 0),
    0,
  );
  const knownUnreadCount = loaded.reduce(
    (sum, source) => sum + (source.state.unreadCount ?? 0),
    0,
  );
  const complete = loaded.every(
    (source) =>
      source.state.state === "ready" || source.state.state === "empty",
  );

  return {
    items: merged.slice(offset, offset + query.pageSize),
    page: query.page,
    pageSize: query.pageSize,
    knownTotal,
    total: complete ? knownTotal : null,
    knownUnreadCount,
    unreadCount: complete ? knownUnreadCount : null,
    completeness: complete ? "complete" : "partial",
    sourceStates: loaded.map((source) => source.state),
    asOfUtc: new Date().toISOString(),
  };
}

async function activeAlertExists(
  sql: AdminSql,
  source: NotificationSource,
  alertKey: string,
): Promise<boolean> {
  if (source === "support") {
    const match = /^support:ticket:([0-9a-f-]{36}):sla$/i.exec(alertKey);
    if (!match) return false;
    const rows = await sql`
      select exists(
        select 1 from admin.support_ticket_queue_v1 q
        where q.ticket_id=${match[1]}::uuid
          and q.status not in ('Resolved','Closed')
          and (q.sla_state in ('Breached','DueSoon') or q.priority='Urgent')
      ) as active
    `;
    return rows[0]?.active === true;
  }
  if (source === "security") {
    const match = /^security:audit:([0-9a-f-]{36})$/i.exec(alertKey);
    if (!match) return false;
    const rows = await sql`
      select exists(
        select 1 from admin.audit_events e
        where e.id=${match[1]}::uuid
          and e.occurred_at_utc >= now() - interval '7 days'
          and (e.result='Failed' or (e.result='Denied' and e.elevated_access=true))
      ) as active
    `;
    return rows[0]?.active === true;
  }
  if (source !== "operations") return false;

  const rows =
    await sql`select * from admin.notification_operations_queue_snapshot()`;
  const row = (rows[0] ?? {}) as Row;
  if (alertKey === "operations:outbox:dead-letter") {
    return numberValue(row.dead_letter_count) > 0;
  }
  if (alertKey === "operations:outbox:stale-lock") {
    return numberValue(row.stale_processing_count) > 0;
  }
  const age = numberValue(row.oldest_ready_age_seconds);
  if (alertKey === "operations:outbox:lag-warning") {
    return age >= 120 && age < 900;
  }
  if (alertKey === "operations:outbox:lag-critical") return age >= 900;
  return false;
}

export function createNotificationCenterStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    list: (
      accountId: string,
      query: NotificationQuery,
      authorizedSources: NotificationSource[],
      correlationId: string,
    ) =>
      listNotifications(
        sql,
        accountId,
        query,
        authorizedSources,
        correlationId,
      ),

    async count(
      accountId: string,
      sources: NotificationSource[],
      correlationId: string,
    ) {
      const result = await listNotifications(
        sql,
        accountId,
        { page: 1, pageSize: 1, sources, unreadOnly: false },
        sources,
        correlationId,
      );
      return {
        knownUnreadCount: result.knownUnreadCount,
        unreadCount: result.unreadCount,
        completeness: result.completeness,
        sourceStates: result.sourceStates,
        asOfUtc: result.asOfUtc,
      };
    },

    hasActiveAlert: (source: NotificationSource, alertKey: string) =>
      activeAlertExists(sql, source, alertKey),

    async setReadState(
      actorAccountId: string,
      payload: NotificationReadStateRequest,
      correlationId: string,
      idempotencyKey: string,
      requestHash: string,
    ) {
      const rows = await sql`
        select admin.set_notification_read_state(
          ${actorAccountId}::uuid,
          ${payload.alertKey}::varchar,
          ${payload.source}::varchar,
          ${payload.read}::boolean,
          ${correlationId}::uuid,
          ${idempotencyKey}::varchar,
          ${requestHash}::varchar
        ) as result
      `;
      return assertNotificationReadStateResult(rows[0]?.result);
    },
  };
}
