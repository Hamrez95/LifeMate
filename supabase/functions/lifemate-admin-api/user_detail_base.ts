import type { AdminSql } from "./database_client.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

export async function getUserDetailBase(sql: AdminSql, accountId: string) {
  const rows = await sql`
    select a.id as account_id, a.status as account_status, a.created_at_utc,
           a.username, link.person_id, profile.display_name, profile.locale, profile.time_zone
    from identity.accounts a
    left join core.account_person_links link
      on link.account_id = a.id and link.link_type = 'Self' and link.status = 'Active'
    left join core.person_profiles profile on profile.person_id = link.person_id
    where a.id = ${accountId}::uuid and a.status <> 'Deleted'
    limit 1
  `;

  const row = rows[0];
  if (!row) return null;
  return {
    accountId: String(row.account_id),
    username: typeof row.username === "string" ? row.username : null,
    status: String(row.account_status),
    createdAtUtc: iso(row.created_at_utc),
    person: typeof row.person_id === "string"
      ? {
        id: row.person_id,
        displayName: typeof row.display_name === "string"
          ? row.display_name
          : null,
        locale: typeof row.locale === "string" ? row.locale : null,
        timeZone: typeof row.time_zone === "string" ? row.time_zone : null,
      }
      : null,
  };
}

export async function listUserEnrollments(sql: AdminSql, accountId: string) {
  const rows = await sql`
    select application.code, application.display_name, enrollment.status,
           enrollment.enrolled_at_utc, enrollment.last_active_at_utc
    from ecosystem.app_enrollments enrollment
    join ecosystem.applications application on application.id = enrollment.application_id
    where enrollment.account_id = ${accountId}::uuid
    order by application.code asc
  `;

  return rows.map((row) => ({
    applicationCode: String(row.code),
    applicationName: String(row.display_name),
    status: String(row.status),
    enrolledAtUtc: iso(row.enrolled_at_utc),
    lastActiveAtUtc: row.last_active_at_utc == null
      ? null
      : iso(row.last_active_at_utc),
  }));
}
