import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { UserDirectoryQuery } from "./directory.ts";
import { listUserDirectory } from "./directory_store.ts";
import { createAdminIdentityResolver } from "./identity_resolution.ts";
import type { StaffProfileInput } from "./staff_profile.ts";
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

export type StaffProfileView = {
  accountId: string;
  username: string;
  displayName: string;
  createdAtUtc: string;
  updatedAtUtc: string;
  usernameChangedAtUtc: string;
};

function asStringArray(rows: readonly Row[], key: string): string[] {
  return rows
    .map((row) => row[key])
    .filter((value): value is string => typeof value === "string");
}

function toIso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function mapStaffProfile(row: Row): StaffProfileView {
  return {
    accountId: String(row.account_id),
    username: String(row.username),
    displayName: String(row.display_name),
    createdAtUtc: toIso(row.created_at_utc),
    updatedAtUtc: toIso(row.updated_at_utc),
    usernameChangedAtUtc: toIso(row.username_changed_at_utc),
  };
}

export function createAdminStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  const identityResolver = createAdminIdentityResolver(databaseUrl);

  async function health(): Promise<void> {
    await sql`select 1 as ready`;
  }

  async function assertActiveMember(accountId: string, query: AdminSql = sql): Promise<void> {
    const rows = await query`
      select 1
      from admin.members
      where account_id=${accountId}::uuid and status='Active'
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(
        403,
        "admin_membership_required",
        "This account is not an active Command Center member.",
      );
    }
  }

  async function getSnapshot(
    accountId: string,
  ): Promise<AdminCapabilitySnapshot> {
    await assertActiveMember(accountId);

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

  async function getOwnStaffProfile(accountId: string): Promise<StaffProfileView | null> {
    await assertActiveMember(accountId);
    const rows = await sql`
      select account_id,username,display_name,created_at_utc,updated_at_utc,username_changed_at_utc
      from admin.staff_profiles
      where account_id=${accountId}::uuid
      limit 1
    `;
    return rows[0] ? mapStaffProfile(rows[0] as Row) : null;
  }

  async function upsertOwnStaffProfile(args: {
    accountId: string;
    input: StaffProfileInput;
    correlationId: string;
    idempotencyKey: string;
    requestHash: string;
  }): Promise<{ profile: StaffProfileView; replayed: boolean }> {
    const { accountId, input, correlationId, idempotencyKey, requestHash } = args;
    const operation = "staff.profile.upsert";

    return await sql.begin(async (tx) => {
      await assertActiveMember(accountId, tx);
      await tx`select pg_advisory_xact_lock(hashtextextended(${accountId + ":" + idempotencyKey}, 0))`;

      const existing = await tx`
        select request_hash,status,response_json
        from admin.idempotency_keys
        where actor_account_id=${accountId}::uuid
          and operation=${operation}
          and idempotency_key=${idempotencyKey}
        for update
      `;
      if (existing[0]) {
        if (existing[0].request_hash !== requestHash) {
          throw new ApiError(
            409,
            "idempotency_conflict",
            "This Idempotency-Key was already used for a different request.",
          );
        }
        if (existing[0].status === "Completed" && existing[0].response_json) {
          const response = existing[0].response_json as Record<string, unknown>;
          return {
            profile: response.profile as StaffProfileView,
            replayed: true,
          };
        }
        throw new ApiError(
          409,
          "idempotency_in_progress",
          "The matching staff profile update is still processing.",
        );
      }

      await tx`
        insert into admin.idempotency_keys(
          actor_account_id,operation,idempotency_key,request_hash,status
        ) values (
          ${accountId}::uuid,${operation},${idempotencyKey},${requestHash},'Processing'
        )
      `;

      const conflict = await tx`
        select account_id
        from admin.staff_profiles
        where username=${input.username}
          and account_id<>${accountId}::uuid
        limit 1
      `;
      if (conflict[0]) {
        await tx`
          update admin.idempotency_keys
          set status='Failed',response_status=409,updated_at_utc=now()
          where actor_account_id=${accountId}::uuid
            and operation=${operation}
            and idempotency_key=${idempotencyKey}
        `;
        throw new ApiError(
          409,
          "staff_username_unavailable",
          "The requested staff username is unavailable.",
        );
      }

      const previous = await tx`
        select username
        from admin.staff_profiles
        where account_id=${accountId}::uuid
        limit 1
      `;
      const usernameChanged = Boolean(
        previous[0] && previous[0].username !== input.username,
      );

      const rows = await tx`
        insert into admin.staff_profiles(account_id,username,display_name)
        values (${accountId}::uuid,${input.username},${input.displayName})
        on conflict (account_id) do update set
          username=excluded.username,
          display_name=excluded.display_name,
          updated_at_utc=now(),
          username_changed_at_utc=case
            when admin.staff_profiles.username is distinct from excluded.username then now()
            else admin.staff_profiles.username_changed_at_utc
          end
        returning account_id,username,display_name,created_at_utc,updated_at_utc,username_changed_at_utc
      `;
      const profile = mapStaffProfile(rows[0] as Row);

      await tx`
        insert into admin.audit_events(
          actor_account_id,action,resource_type,resource_id,result,reason,
          correlation_id,request_id,elevated_access,metadata_json
        ) values (
          ${accountId}::uuid,'admin.staff_profile.upsert','admin_staff_profile',${accountId},
          'Succeeded','Self-service workforce profile update',${correlationId}::uuid,
          ${idempotencyKey},false,
          ${JSON.stringify({ usernameChanged })}::jsonb
        )
      `;

      const response = { profile, replayed: false };
      await tx`
        update admin.idempotency_keys
        set status='Completed',response_status=200,response_json=${JSON.stringify(response)}::jsonb,
            updated_at_utc=now()
        where actor_account_id=${accountId}::uuid
          and operation=${operation}
          and idempotency_key=${idempotencyKey}
      `;
      return response;
    });
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
    resolveAccountId: identityResolver.resolveAccountId,
    getSnapshot,
    getOwnStaffProfile,
    upsertOwnStaffProfile,
    bootstrapFounder,
    listAudit,
    listUsers,
  };
}
