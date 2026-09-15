import type { AdminSql } from "./database_client.ts";
import type { StaffDirectoryQuery } from "./staff_directory.ts";

export type StaffDirectoryItem = {
  accountId: string;
  username: string | null;
  displayName: string | null;
  membershipStatus: string;
  roles: Array<{ code: string; displayName: string }>;
  effectivePermissionCount: number;
  createdAtUtc: string;
  lastAccessChangeAtUtc: string | null;
  lastAdminActivity:
    | { action: string; result: string; occurredAtUtc: string }
    | null;
  mfaPosture: "unknown";
};

export type StaffDetail = StaffDirectoryItem & {
  roleHistory: Array<{
    roleCode: string;
    roleDisplayName: string;
    startsAtUtc: string;
    expiresAtUtc: string | null;
    revokedAtUtc: string | null;
  }>;
  effectivePermissions: Array<
    { code: string; domain: string; riskLevel: string }
  >;
  activity: Array<{
    id: string;
    action: string;
    result: string;
    resourceType: string;
    occurredAtUtc: string;
  }>;
};

type Row = Record<string, unknown>;

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
function nullableIso(value: unknown): string | null {
  return value == null ? null : iso(value);
}
function nullableString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}
function parseRoles(
  value: unknown,
): Array<{ code: string; displayName: string }> {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== "object") return [];
    const row = entry as Record<string, unknown>;
    return typeof row.code === "string" && typeof row.displayName === "string"
      ? [{ code: row.code, displayName: row.displayName }]
      : [];
  });
}
function mapDirectoryItem(row: Row): StaffDirectoryItem {
  return {
    accountId: String(row.account_id),
    username: nullableString(row.username),
    displayName: nullableString(row.display_name),
    membershipStatus: String(row.membership_status),
    roles: parseRoles(row.roles),
    effectivePermissionCount: Number(row.effective_permission_count ?? 0),
    createdAtUtc: iso(row.created_at_utc),
    lastAccessChangeAtUtc: nullableIso(row.last_access_change_at_utc),
    lastAdminActivity: row.last_activity_action == null ? null : {
      action: String(row.last_activity_action),
      result: String(row.last_activity_result),
      occurredAtUtc: iso(row.last_activity_at_utc),
    },
    mfaPosture: "unknown",
  };
}

export async function listStaffDirectory(
  sql: AdminSql,
  query: StaffDirectoryQuery,
) {
  const cursorCreated = query.cursor?.createdAtUtc ?? null;
  const cursorAccount = query.cursor?.accountId ?? null;
  const rows = await sql`
    with current_roles as (
      select mr.account_id,
             jsonb_agg(jsonb_build_object('code', r.code, 'displayName', r.display_name) order by r.rank, r.code) as roles
      from admin.member_roles mr
      join admin.roles r on r.id = mr.role_id
      where mr.revoked_at_utc is null
        and mr.starts_at_utc <= now()
        and (mr.expires_at_utc is null or mr.expires_at_utc > now())
        and r.status = 'Active'
      group by mr.account_id
    ), permission_counts as (
      select mr.account_id, count(distinct rp.permission_code)::integer as permission_count
      from admin.member_roles mr
      join admin.roles r on r.id = mr.role_id and r.status='Active'
      join admin.role_permissions rp on rp.role_id = r.id
      join admin.permissions p on p.code = rp.permission_code and p.role_assignable = true
      where mr.revoked_at_utc is null
        and mr.starts_at_utc <= now()
        and (mr.expires_at_utc is null or mr.expires_at_utc > now())
      group by mr.account_id
    )
    select m.account_id, sp.username, sp.display_name, m.status as membership_status,
           coalesce(cr.roles, '[]'::jsonb) as roles,
           coalesce(pc.permission_count,0) as effective_permission_count,
           m.created_at_utc,
           greatest(m.updated_at_utc, coalesce(max_role.changed_at, m.created_at_utc)) as last_access_change_at_utc,
           last_activity.action as last_activity_action,
           last_activity.result as last_activity_result,
           last_activity.occurred_at_utc as last_activity_at_utc
    from admin.members m
    left join admin.staff_profiles sp on sp.account_id=m.account_id
    left join current_roles cr on cr.account_id=m.account_id
    left join permission_counts pc on pc.account_id=m.account_id
    left join lateral (
      select max(greatest(mr.created_at_utc, coalesce(mr.revoked_at_utc,mr.created_at_utc))) as changed_at
      from admin.member_roles mr where mr.account_id=m.account_id
    ) max_role on true
    left join lateral (
      select ae.action, ae.result, ae.occurred_at_utc
      from admin.audit_events ae
      where ae.actor_account_id=m.account_id
      order by ae.occurred_at_utc desc, ae.id desc limit 1
    ) last_activity on true
    where (${query.status}::text is null or m.status=${query.status}::varchar)
      and (${query.roleCode}::text is null or exists (
        select 1 from admin.member_roles fmr join admin.roles fr on fr.id=fmr.role_id
        where fmr.account_id=m.account_id and fr.code=${query.roleCode}::text
          and fmr.revoked_at_utc is null and fmr.starts_at_utc<=now()
          and (fmr.expires_at_utc is null or fmr.expires_at_utc>now())
      ))
      and (${query.q}::text is null or
        strpos(lower(coalesce(sp.username,'')), lower(${query.q}::text)) > 0 or
        strpos(lower(coalesce(sp.display_name,'')), lower(${query.q}::text)) > 0)
      and (${cursorCreated}::timestamptz is null or
        (m.created_at_utc, m.account_id) < (${cursorCreated}::timestamptz, ${cursorAccount}::uuid))
    order by m.created_at_utc desc, m.account_id desc
    limit ${query.pageSize + 1}
  `;
  return (rows as unknown as Row[]).map(mapDirectoryItem);
}

export async function getStaffDetail(
  sql: AdminSql,
  accountId: string,
): Promise<StaffDetail | null> {
  const baseRows = await sql`
    select m.account_id, sp.username, sp.display_name, m.status as membership_status,
           m.created_at_utc,
           greatest(m.updated_at_utc, coalesce(max_role.changed_at,m.created_at_utc)) as last_access_change_at_utc,
           coalesce(current_roles.roles,'[]'::jsonb) as roles,
           coalesce(permission_count.permission_count,0) as effective_permission_count,
           last_activity.action as last_activity_action,
           last_activity.result as last_activity_result,
           last_activity.occurred_at_utc as last_activity_at_utc
    from admin.members m
    left join admin.staff_profiles sp on sp.account_id=m.account_id
    left join lateral (
      select jsonb_agg(jsonb_build_object('code',r.code,'displayName',r.display_name) order by r.rank,r.code) as roles
      from admin.member_roles mr join admin.roles r on r.id=mr.role_id
      where mr.account_id=m.account_id and mr.revoked_at_utc is null and mr.starts_at_utc<=now()
        and (mr.expires_at_utc is null or mr.expires_at_utc>now()) and r.status='Active'
    ) current_roles on true
    left join lateral (
      select count(distinct rp.permission_code)::integer as permission_count
      from admin.member_roles mr join admin.roles r on r.id=mr.role_id and r.status='Active'
      join admin.role_permissions rp on rp.role_id=r.id join admin.permissions p on p.code=rp.permission_code and p.role_assignable=true
      where mr.account_id=m.account_id and mr.revoked_at_utc is null and mr.starts_at_utc<=now()
        and (mr.expires_at_utc is null or mr.expires_at_utc>now())
    ) permission_count on true
    left join lateral (
      select max(greatest(mr.created_at_utc,coalesce(mr.revoked_at_utc,mr.created_at_utc))) as changed_at
      from admin.member_roles mr where mr.account_id=m.account_id
    ) max_role on true
    left join lateral (
      select ae.action,ae.result,ae.occurred_at_utc from admin.audit_events ae
      where ae.actor_account_id=m.account_id order by ae.occurred_at_utc desc,ae.id desc limit 1
    ) last_activity on true
    where m.account_id=${accountId}::uuid
  `;
  const base = (baseRows as unknown as Row[])[0];
  if (!base) return null;

  const [roleRows, permissionRows, activityRows] = await Promise.all([
    sql`select r.code as role_code,r.display_name as role_display_name,mr.starts_at_utc,mr.expires_at_utc,mr.revoked_at_utc
        from admin.member_roles mr join admin.roles r on r.id=mr.role_id where mr.account_id=${accountId}::uuid
        order by mr.created_at_utc desc,mr.id desc limit 100`,
    sql`select distinct p.code,p.domain,p.risk_level from admin.member_roles mr join admin.roles r on r.id=mr.role_id and r.status='Active'
        join admin.role_permissions rp on rp.role_id=r.id join admin.permissions p on p.code=rp.permission_code and p.role_assignable=true
        where mr.account_id=${accountId}::uuid and mr.revoked_at_utc is null and mr.starts_at_utc<=now()
          and (mr.expires_at_utc is null or mr.expires_at_utc>now()) order by p.domain,p.code`,
    sql`select id,action,result,resource_type,occurred_at_utc from admin.audit_events
        where actor_account_id=${accountId}::uuid or (resource_type in ('admin_member','admin_member_role') and resource_id=${accountId})
        order by occurred_at_utc desc,id desc limit 100`,
  ]);

  return {
    ...mapDirectoryItem(base),
    roleHistory: (roleRows as unknown as Row[]).map((row) => ({
      roleCode: String(row.role_code),
      roleDisplayName: String(row.role_display_name),
      startsAtUtc: iso(row.starts_at_utc),
      expiresAtUtc: nullableIso(row.expires_at_utc),
      revokedAtUtc: nullableIso(row.revoked_at_utc),
    })),
    effectivePermissions: (permissionRows as unknown as Row[]).map((row) => ({
      code: String(row.code),
      domain: String(row.domain),
      riskLevel: String(row.risk_level),
    })),
    activity: (activityRows as unknown as Row[]).map((row) => ({
      id: String(row.id),
      action: String(row.action),
      result: String(row.result),
      resourceType: String(row.resource_type),
      occurredAtUtc: iso(row.occurred_at_utc),
    })),
  };
}

export async function auditStaffDetailRead(
  sql: AdminSql,
  actorAccountId: string,
  targetAccountId: string,
  correlationId: string,
) {
  await sql`insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
    values(${actorAccountId}::uuid,'staff.detail.read','admin_member',${targetAccountId},'Allowed','Canonical staff detail read',${correlationId}::uuid,false,'{}'::jsonb)`;
}
