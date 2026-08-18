import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { UserDirectoryQuery } from "./directory.ts";
import { listUserDirectory } from "./directory_store.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export type AuditEventView = {
  id: string;
  actorAccountId: string | null;
  action: string;
  resourceType: string;
  resourceId: string | null;
  result: string;
  reason: string | null;
  correlationId: string;
  requestId: string | null;
  elevatedAccess: boolean;
  occurredAtUtc: string;
};

function asStringArray(rows: readonly Row[], key: string): string[] {
  return rows
    .map((row) => row[key])
    .filter((value): value is string => typeof value === "string");
}

export function createAdminStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);

  async function health(): Promise<void> {
    await sql`select 1 as ready`;
  }

  async function getSnapshot(
    accountId: string,
  ): Promise<AdminCapabilitySnapshot> {
    const memberRows = await sql`
      select account_id
      from admin.members
      where account_id=${accountId}::uuid and status='Active'
      limit 1
    `;
    if (!memberRows[0]) {
      throw new ApiError(
        403,
        "admin_membership_required",
        "This account is not an active Command Center member.",
      );
    }

    const roleRows = await sql`
      select distinct r.code
      from admin.member_roles mr
      join admin.roles r on r.id=mr.role_id
      where mr.account_id=${accountId}::uuid
        and r.status='Active'
        and mr.revoked_at_utc is null
        and mr.starts_at_utc <= now()
        and (mr.expires_at_utc is null or mr.expires_at_utc > now())
      order by r.code
    `;
    const permissionRows = await sql`
      select distinct p.code
      from admin.member_roles mr
      join admin.roles r on r.id=mr.role_id
      join admin.role_permissions rp on rp.role_id=r.id
      join admin.permissions p on p.code=rp.permission_code
      where mr.account_id=${accountId}::uuid
        and r.status='Active'
        and p.role_assignable=true
        and mr.revoked_at_utc is null
        and mr.starts_at_utc <= now()
        and (mr.expires_at_utc is null or mr.expires_at_utc > now())
      order by p.code
    `;

    return {
      accountId,
      roles: asStringArray(roleRows as unknown as Row[], "code"),
      permissions: asStringArray(permissionRows as unknown as Row[], "code"),
    };
  }

  async function bootstrapFounder(
    accountId: string,
    correlationId: string,
    idempotencyKey: string,
  ): Promise<{ created: boolean }> {
    return await sql.begin(async (tx) => {
      await tx`select pg_advisory_xact_lock(hashtext('lifemate-admin-founder-bootstrap'))`;
      const existingMembers =
        await tx`select count(*)::integer as count from admin.members`;
      const count = Number(existingMembers[0]?.count ?? 0);

      if (count > 0) {
        const current = await tx`
          select 1
          from admin.members m
          join admin.member_roles mr on mr.account_id=m.account_id
          join admin.roles r on r.id=mr.role_id
          where m.account_id=${accountId}::uuid
            and m.status='Active'
            and r.code='founder'
            and r.status='Active'
            and mr.revoked_at_utc is null
            and mr.starts_at_utc <= now()
            and (mr.expires_at_utc is null or mr.expires_at_utc > now())
          limit 1
        `;
        if (current[0]) return { created: false };
        throw new ApiError(
          409,
          "admin_bootstrap_closed",
          "The Command Center founder bootstrap is already complete.",
        );
      }

      const founderRows = await tx`
        select id from admin.roles where code='founder' and status='Active' limit 1
      `;
      const founderRoleId = founderRows[0]?.id;
      if (typeof founderRoleId !== "string") {
        throw new ApiError(
          503,
          "admin_role_unavailable",
          "Founder role is unavailable.",
        );
      }

      await tx`
        insert into admin.members(account_id,status,created_by_account_id)
        values (${accountId}::uuid,'Active',${accountId}::uuid)
      `;
      await tx`
        insert into admin.member_roles(account_id,role_id,granted_by_account_id)
        values (${accountId}::uuid,${founderRoleId}::uuid,${accountId}::uuid)
      `;
      await tx`
        insert into admin.audit_events(
          actor_account_id,action,resource_type,resource_id,result,reason,
          correlation_id,request_id,elevated_access,metadata_json
        ) values (
          ${accountId}::uuid,'admin.bootstrap.founder','admin_member',${accountId},
          'Succeeded','Initial founder bootstrap',${correlationId}::uuid,
          ${idempotencyKey},false,'{"method":"configured_auth_subject"}'::jsonb
        )
      `;
      return { created: true };
    });
  }

  async function listAudit(limit: number): Promise<AuditEventView[]> {
    const rows = await sql`
      select id,actor_account_id,action,resource_type,resource_id,result,reason,
             correlation_id,request_id,elevated_access,occurred_at_utc
      from admin.audit_events
      order by occurred_at_utc desc, id desc
      limit ${limit}
    `;
    return rows.map((row) => ({
      id: String(row.id),
      actorAccountId: typeof row.actor_account_id === "string"
        ? row.actor_account_id
        : null,
      action: String(row.action),
      resourceType: String(row.resource_type),
      resourceId: typeof row.resource_id === "string" ? row.resource_id : null,
      result: String(row.result),
      reason: typeof row.reason === "string" ? row.reason : null,
      correlationId: String(row.correlation_id),
      requestId: typeof row.request_id === "string" ? row.request_id : null,
      elevatedAccess: row.elevated_access === true,
      occurredAtUtc: row.occurred_at_utc instanceof Date
        ? row.occurred_at_utc.toISOString()
        : String(row.occurred_at_utc),
    }));
  }

  async function listUsers(query: UserDirectoryQuery) {
    return await listUserDirectory(sql, query);
  }

  return {
    health,
    getSnapshot,
    bootstrapFounder,
    listAudit,
    listUsers,
  };
}
