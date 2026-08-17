import { getAdminSql } from "./database_client.ts";
import {
  type AdminPermissionMatrixRow,
  type AdminRoleMatrixRow,
  type AdminRolePermissionAssignmentRow,
  buildAdminRbacMatrix,
} from "./security_rbac.ts";

type Row = Record<string, unknown>;

function record(value: unknown, label: string): Row {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value as Row;
}

function records(value: unknown, label: string): Row[] {
  if (!Array.isArray(value)) {
    throw new Error(`${label} must be an array`);
  }
  return value.map((item) => record(item, label));
}

function requiredString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} must be a non-empty string`);
  }
  return value;
}

function role(row: Row): AdminRoleMatrixRow {
  const status = requiredString(row.status, "admin role status");
  const rank = Number(row.rank);
  if (status !== "Active" && status !== "Disabled") {
    throw new Error("admin role has an invalid status");
  }
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
    status,
    isSystem: row.isSystem,
  };
}

function permission(row: Row): AdminPermissionMatrixRow {
  const riskLevel = requiredString(
    row.riskLevel,
    "admin permission risk level",
  );
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
  return {
    code: requiredString(row.code, "admin permission code"),
    domain: requiredString(row.domain, "admin permission domain"),
    riskLevel,
    roleAssignable: row.roleAssignable,
    description: requiredString(
      row.description,
      "admin permission description",
    ),
  };
}

function assignment(row: Row): AdminRolePermissionAssignmentRow {
  return {
    roleCode: requiredString(row.roleCode, "admin assignment role code"),
    permissionCode: requiredString(
      row.permissionCode,
      "admin assignment permission code",
    ),
  };
}

export function createSecurityRbacStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async getRolePermissionMatrix() {
      const rows = await sql`
        select
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'code', r.code,
                  'displayName', r.display_name,
                  'rank', r.rank,
                  'status', r.status,
                  'isSystem', r.is_system
                )
                order by r.rank asc, r.code asc
              )
              from admin.roles r
            ),
            '[]'::jsonb
          ) as roles,
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
              from admin.permissions p
            ),
            '[]'::jsonb
          ) as permissions,
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'roleCode', r.code,
                  'permissionCode', p.code
                )
                order by r.rank asc, r.code asc, p.domain asc, p.code asc
              )
              from admin.role_permissions rp
              join admin.roles r on r.id=rp.role_id
              join admin.permissions p on p.code=rp.permission_code
            ),
            '[]'::jsonb
          ) as assignments
      `;

      const row = record(
        (rows as unknown as Row[])[0],
        "RBAC matrix database row",
      );
      return buildAdminRbacMatrix(
        records(row.roles, "RBAC roles").map(role),
        records(row.permissions, "RBAC permissions").map(permission),
        records(row.assignments, "RBAC assignments").map(assignment),
      );
    },
  };
}
