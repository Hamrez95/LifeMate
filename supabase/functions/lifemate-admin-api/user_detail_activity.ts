import type { AdminSql } from "./database_client.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

export async function getUserAdminActivitySummary(sql: AdminSql, accountId: string) {
  const countRows = await sql`
    select count(*)::integer as total
    from admin.audit_events
    where resource_id = ${accountId}
  `;
  const latestRows = await sql`
    select id, action, result, occurred_at_utc
    from admin.audit_events
    where resource_id = ${accountId}
    order by occurred_at_utc desc, id desc
    limit 5
  `;

  return {
    total: Number(countRows[0]?.total ?? 0),
    latest: latestRows.map((row) => ({
      id: String(row.id),
      action: String(row.action),
      result: String(row.result),
      occurredAtUtc: iso(row.occurred_at_utc),
    })),
  };
}
