import { getAdminSql } from "./database_client.ts";
import {
  type AdminPermissionMatrixRow,
  type AdminRoleMatrixRow,
  type AdminRolePermissionAssignmentRow,
  buildAdminRbacMatrix,
} from "./security_rbac.ts";

type Row = Record<string, unknown>;

function role(row: Row): AdminRoleMatrixRow {
  const status = String(row.status);
  if (status !== "Active" && status !== "Disabled") {
    throw new Error("admin role has an invalid status");
  }
  return {
    code: String(row.code),
    displayName: String(row.display_name),
    rank: Number(row.rank),
    status,
    isSystem: row.is_system === true,
  };
}

function permission(row: Row): AdminPermissionMatrixRow {
  const riskLevel = String(row.risk_level);
  if (
    riskLevel !== "STANDARD" &&
    riskLevel !== "SENSITIVE" &&
    riskLevel !== "HIGH_RISK" &&
    riskLevel !== "ELEVATED"
  ) {
    throw new Error("admin permission has an invalid risk level");
  }
  return {
    code: String(row.code),
    domain: String(row.domain),
    riskLevel,
    roleAssignable: row.role_assignable === true,
    description: String(row.description),
  };
}

export function createSecurityRbacStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async getRolePermissionMatrix() {
      const [roleRows, permissionRows, assignmentRows] = await Promise.all([
        sql`
          select code, display_name, rank, status, is_system
          from admin.roles
          order by rank asc, code asc
        `,
        sql`
          select code, domain, risk_level, role_assignable, description
          from admin.permissions
          order by domain asc, risk_level asc, code asc
        `,
        sql`
          select r.code as role_code, p.code as permission_code
          from admin.role_permissions rp
          join admin.roles r on r.id=rp.role_id
          join admin.permissions p on p.code=rp.permission_code
          order by r.rank asc, r.code asc, p.domain asc, p.code asc
        `,
      ]);

      return buildAdminRbacMatrix(
        (roleRows as unknown as Row[]).map(role),
        (permissionRows as unknown as Row[]).map(permission),
        (assignmentRows as unknown as Row[]).map(
          (row): AdminRolePermissionAssignmentRow => ({
            roleCode: String(row.role_code),
            permissionCode: String(row.permission_code),
          }),
        ),
      );
    },
  };
}
