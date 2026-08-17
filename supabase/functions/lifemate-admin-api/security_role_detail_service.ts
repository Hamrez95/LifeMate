import { getAdminSql } from "./database_client.ts";
import {
  type AdminMemberStatus,
  type AdminRoleStatus,
  classifyAdminMembership,
  rolePermissionDetail,
} from "./security_role_detail.ts";

type Row = Record<string, unknown>;

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function record(value: unknown, label: string): Row {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value as Row;
}

function records(value: unknown, label: string): Row[] {
  if (!Array.isArray(value)) throw new Error(`${label} must be an array`);
  return value.map((item) => record(item, label));
}

function requiredString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} must be a non-empty string`);
  }
  return value;
}

function uuid(value: unknown, label: string): string {
  const parsed = requiredString(value, label);
  if (!UUID.test(parsed)) throw new Error(`${label} must be a UUID`);
  return parsed;
}

function timestamp(value: unknown, label: string): string {
  const parsed = requiredString(value, label);
  if (Number.isNaN(Date.parse(parsed))) {
    throw new Error(`${label} must be a timestamp`);
  }
  return parsed;
}

function nullableTimestamp(value: unknown, label: string): string | null {
  return value === null ? null : timestamp(value, label);
}

function roleStatus(value: unknown): AdminRoleStatus {
  if (value !== "Active" && value !== "Disabled") {
    throw new Error("admin role has an invalid status");
  }
  return value;
}

function memberStatus(value: unknown): AdminMemberStatus {
  if (value !== "Active" && value !== "Disabled" && value !== "Revoked") {
    throw new Error("admin member has an invalid status");
  }
  return value;
}

function stringArray(value: unknown, label: string): string[] {
  if (!Array.isArray(value)) throw new Error(`${label} must be an array`);
  return value.map((item) => requiredString(item, label));
}

function parseRole(value: unknown) {
  const row = record(value, "role detail role");
  const rank = Number(row.rank);
  if (!Number.isInteger(rank) || rank < 1 || rank > 1000) {
    throw new Error("admin role has an invalid rank");
  }
  if (typeof row.isSystem !== "boolean") {
    throw new Error("admin role has an invalid system flag");
  }
  return {
    code: requiredString(row.code, "admin role code"),
    displayName: requiredString(row.displayName, "admin role display name"),
    rank,
    status: roleStatus(row.status),
    isSystem: row.isSystem,
  };
}

function parsePermission(value: unknown, status: AdminRoleStatus) {
  const row = record(value, "role detail permission");
  const riskLevel = requiredString(row.riskLevel, "permission risk level");
  if (
    riskLevel !== "STANDARD" &&
    riskLevel !== "SENSITIVE" &&
    riskLevel !== "HIGH_RISK" &&
    riskLevel !== "ELEVATED"
  ) {
    throw new Error("admin permission has an invalid risk level");
  }
  if (typeof row.roleAssignable !== "boolean") {
    throw new Error("admin permission has an invalid role-assignable flag");
  }
  return rolePermissionDetail(status, {
    code: requiredString(row.code, "permission code"),
    domain: requiredString(row.domain, "permission domain"),
    riskLevel,
    roleAssignable: row.roleAssignable,
    description: requiredString(row.description, "permission description"),
  });
}

function parseEffectivePermission(value: unknown) {
  const row = record(value, "effective permission");
  const sources = stringArray(
    row.sourceRoleCodes,
    "effective permission source roles",
  );
  if (sources.length === 0) {
    throw new Error("effective permission must have at least one source role");
  }
  return {
    code: requiredString(row.code, "effective permission code"),
    sourceRoleCodes: [...new Set(sources)].sort(),
  };
}

function parseMembership(
  value: unknown,
  status: AdminRoleStatus,
  at: Date,
) {
  const row = record(value, "role membership");
  const currentRoleCodes = [
    ...new Set(stringArray(row.currentRoleCodes, "current role codes")),
  ].sort();
  const effectivePermissions = records(
    row.effectivePermissions,
    "effective permissions",
  ).map(parseEffectivePermission);
  effectivePermissions.sort((a, b) => a.code.localeCompare(b.code));

  const parsedMemberStatus = memberStatus(row.memberStatus);
  const startsAtUtc = timestamp(row.startsAtUtc, "membership start");
  const expiresAtUtc = nullableTimestamp(row.expiresAtUtc, "membership expiry");
  const revokedAtUtc = nullableTimestamp(
    row.revokedAtUtc,
    "membership revocation",
  );
  const state = classifyAdminMembership(
    parsedMemberStatus,
    status,
    { startsAtUtc, expiresAtUtc, revokedAtUtc },
    at,
  );

  return {
    membershipId: uuid(row.membershipId, "membership id"),
    accountId: uuid(row.accountId, "member account id"),
    memberStatus: parsedMemberStatus,
    startsAtUtc,
    expiresAtUtc,
    revokedAtUtc,
    createdAtUtc: timestamp(row.createdAtUtc, "membership creation"),
    state,
    effective: state === "active",
    currentRoleCodes,
    effectivePermissions,
  };
}

export function createSecurityRoleDetailStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async getRoleDetail(roleCode: string, at = new Date()) {
      const atUtc = at.toISOString();
      const rows = await sql`
        select
          (
            select jsonb_build_object(
              'code', r.code,
              'displayName', r.display_name,
              'rank', r.rank,
              'status', r.status,
              'isSystem', r.is_system
            )
            from admin.roles r
            where r.code = ${roleCode}
          ) as role,
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'code', p.code,
                  'domain', p.domain,
                  'riskLevel', p.risk_level,
                  'roleAssignable', p.role_assignable,
                  'description', p.description
                )
                order by p.domain asc, p.code asc
              )
              from admin.roles r
              join admin.role_permissions rp on rp.role_id = r.id
              join admin.permissions p on p.code = rp.permission_code
              where r.code = ${roleCode}
            ),
            '[]'::jsonb
          ) as permissions,
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'membershipId', mr.id,
                  'accountId', m.account_id,
                  'memberStatus', m.status,
                  'startsAtUtc', mr.starts_at_utc,
                  'expiresAtUtc', mr.expires_at_utc,
                  'revokedAtUtc', mr.revoked_at_utc,
                  'createdAtUtc', mr.created_at_utc,
                  'currentRoleCodes', coalesce(
                    (
                      select jsonb_agg(current_role.code order by current_role.code)
                      from (
                        select distinct r2.code
                        from admin.member_roles mr2
                        join admin.roles r2 on r2.id = mr2.role_id
                        where mr2.account_id = m.account_id
                          and m.status = 'Active'
                          and r2.status = 'Active'
                          and mr2.revoked_at_utc is null
                          and mr2.starts_at_utc <= ${atUtc}::timestamptz
                          and (mr2.expires_at_utc is null or mr2.expires_at_utc > ${atUtc}::timestamptz)
                      ) current_role
                    ),
                    '[]'::jsonb
                  ),
                  'effectivePermissions', coalesce(
                    (
                      select jsonb_agg(
                        jsonb_build_object(
                          'code', effective_permission.code,
                          'sourceRoleCodes', effective_permission.source_role_codes
                        )
                        order by effective_permission.code
                      )
                      from (
                        select
                          p2.code,
                          array_agg(distinct r2.code order by r2.code) as source_role_codes
                        from admin.member_roles mr2
                        join admin.roles r2 on r2.id = mr2.role_id
                        join admin.role_permissions rp2 on rp2.role_id = r2.id
                        join admin.permissions p2 on p2.code = rp2.permission_code
                        where mr2.account_id = m.account_id
                          and m.status = 'Active'
                          and r2.status = 'Active'
                          and mr2.revoked_at_utc is null
                          and mr2.starts_at_utc <= ${atUtc}::timestamptz
                          and (mr2.expires_at_utc is null or mr2.expires_at_utc > ${atUtc}::timestamptz)
                          and p2.role_assignable = true
                        group by p2.code
                      ) effective_permission
                    ),
                    '[]'::jsonb
                  )
                )
                order by m.account_id asc, mr.created_at_utc desc, mr.id desc
              )
              from admin.member_roles mr
              join admin.members m on m.account_id = mr.account_id
              join admin.roles r on r.id = mr.role_id
              where r.code = ${roleCode}
            ),
            '[]'::jsonb
          ) as memberships
      `;

      const row = record(
        (rows as unknown as Row[])[0],
        "role detail database row",
      );
      if (row.role === null) return null;
      const parsedRole = parseRole(row.role);
      const permissions = records(row.permissions, "role permissions").map((
        permission,
      ) => parsePermission(permission, parsedRole.status));
      const memberships = records(row.memberships, "role memberships").map((
        membership,
      ) => parseMembership(membership, parsedRole.status, at));

      return {
        role: parsedRole,
        permissions,
        memberships,
        evaluationAtUtc: atUtc,
        source: {
          kind: "canonical" as const,
          label: "LifeMate admin RBAC control plane",
          definitionVersion: 1,
        },
      };
    },
  };
}
