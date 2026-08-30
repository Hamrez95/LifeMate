import type { AuditQuery } from "./audit.ts";
import { encodeAuditCursor } from "./audit.ts";
import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { UserDirectoryQuery } from "./directory.ts";
import { listUserDirectory } from "./directory_store.ts";
import { createAdminIdentityResolver } from "./identity_resolution.ts";
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

export type AuditPage = {
  events: AuditEventView[];
  nextCursor: string | null;
};

function asStringArray(rows: readonly Row[], key: string): string[] {
  return rows
    .map((row) => row[key])
    .filter((value): value is string => typeof value === "string");
}

function asStringArrayValue(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function mapAuditEvent(row: Row): AuditEventView {
  return {
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
  };
}

export function createAdminStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  const identityResolver = createAdminIdentityResolver(databaseUrl);

  async function health(): Promise<void> {
    await sql`select 1 as ready`;
  }

  async function getSnapshot(
    accountId: string,
  ): Promise<AdminCapabilitySnapshot> {
    const snapshotRows = await sql`
      select
        exists(
          select 1
          from admin.members m
          where m.account_id=${accountId}::uuid
            and m.status='Active'
        ) as is_active_member,
        coalesce(
          array(
            select distinct r.code
            from admin.member_roles mr
            join admin.roles r on r.id=mr.role_id
            where mr.account_id=${accountId}::uuid
              and r.status='Active'
              and mr.revoked_at_utc is null
              and mr.starts_at_utc <= now()
              and (mr.expires_at_utc is null or mr.expires_at_utc > now())
            order by r.code
          ),
          array[]::text[]
        ) as roles,
        coalesce(
          array(
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
          ),
          array[]::text[]
        ) as permissions
    `;
    const snapshot = snapshotRows[0] as Row | undefined;
    if (snapshot?.is_active_member !== true) {
      throw new ApiError(
        403,
        "admin_membership_required",
        "This account is not an active Command Center member.",
      );
    }

    return {
      accountId,
      roles: asStringArrayValue(snapshot.roles),
      permissions: asStringArrayValue(snapshot.permissions),
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

  async function listAudit(query: AuditQuery): Promise<AuditPage> {
    const cursorOccurredAtUtc = query.cursor?.occurredAtUtc ?? null;
    const cursorId = query.cursor?.id ?? null;
    const rows = await sql`
      select id,actor_account_id,action,resource_type,resource_id,result,reason,
             correlation_id,request_id,elevated_access,occurred_at_utc
      from admin.audit_events
      where (${query.fromUtc}::timestamptz is null or occurred_at_utc >= ${query.fromUtc}::timestamptz)
        and (${query.toUtc}::timestamptz is null or occurred_at_utc <= ${query.toUtc}::timestamptz)
        and (
          ${cursorOccurredAtUtc}::timestamptz is null
          or (occurred_at_utc, id) < (${cursorOccurredAtUtc}::timestamptz, ${cursorId}::uuid)
        )
      order by occurred_at_utc desc, id desc
      limit ${query.limit + 1}
    `;

    const mapped = (rows as unknown as Row[]).map(mapAuditEvent);
    const hasMore = mapped.length > query.limit;
    const events = hasMore ? mapped.slice(0, query.limit) : mapped;
    const last = events.at(-1);
    return {
      events,
      nextCursor: hasMore && last
        ? encodeAuditCursor({ occurredAtUtc: last.occurredAtUtc, id: last.id })
        : null,
    };
  }

  async function listUsers(query: UserDirectoryQuery) {
    return await listUserDirectory(sql, query);
  }

  return {
    health,
    resolveAccountId: identityResolver.resolveAccountId,
    getSnapshot,
    bootstrapFounder,
    listAudit,
    listUsers,
  };
}
