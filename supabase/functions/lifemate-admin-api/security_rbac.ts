export type AdminRoleMatrixRow = {
  code: string;
  displayName: string;
  rank: number;
  status: "Active" | "Disabled";
  isSystem: boolean;
};

export type AdminPermissionMatrixRow = {
  code: string;
  domain: string;
  riskLevel: "STANDARD" | "SENSITIVE" | "HIGH_RISK" | "ELEVATED";
  roleAssignable: boolean;
  description: string;
};

export type AdminRolePermissionAssignmentRow = {
  roleCode: string;
  permissionCode: string;
};

export type AdminRolePermissionAssignment = {
  roleCode: string;
  permissionCode: string;
  source: "direct";
  effective: boolean;
  blockedReason: "role_disabled" | "permission_not_role_assignable" | null;
};

export type AdminPermissionGroup = {
  domain: string;
  permissions: AdminPermissionMatrixRow[];
};

const RISK_ORDER: Record<AdminPermissionMatrixRow["riskLevel"], number> = {
  STANDARD: 1,
  SENSITIVE: 2,
  HIGH_RISK: 3,
  ELEVATED: 4,
};

function compareRoles(a: AdminRoleMatrixRow, b: AdminRoleMatrixRow): number {
  return a.rank - b.rank || a.code.localeCompare(b.code);
}

function comparePermissions(
  a: AdminPermissionMatrixRow,
  b: AdminPermissionMatrixRow,
): number {
  return (
    a.domain.localeCompare(b.domain) ||
    RISK_ORDER[a.riskLevel] - RISK_ORDER[b.riskLevel] ||
    a.code.localeCompare(b.code)
  );
}

export function buildAdminRbacMatrix(
  rawRoles: readonly AdminRoleMatrixRow[],
  rawPermissions: readonly AdminPermissionMatrixRow[],
  rawAssignments: readonly AdminRolePermissionAssignmentRow[],
) {
  const roles = [...rawRoles].sort(compareRoles);
  const permissions = [...rawPermissions].sort(comparePermissions);
  const roleByCode = new Map(roles.map((role) => [role.code, role]));
  const permissionByCode = new Map(
    permissions.map((permission) => [permission.code, permission]),
  );

  const seen = new Set<string>();
  const assignments: AdminRolePermissionAssignment[] = [];
  for (const assignment of rawAssignments) {
    const role = roleByCode.get(assignment.roleCode);
    const permission = permissionByCode.get(assignment.permissionCode);
    if (!role || !permission) continue;

    const key = `${role.code}\u0000${permission.code}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const blockedReason = role.status !== "Active"
      ? ("role_disabled" as const)
      : !permission.roleAssignable
      ? ("permission_not_role_assignable" as const)
      : null;

    assignments.push({
      roleCode: role.code,
      permissionCode: permission.code,
      source: "direct",
      effective: blockedReason === null,
      blockedReason,
    });
  }
  assignments.sort((a, b) => {
    const roleCompare = compareRoles(
      roleByCode.get(a.roleCode)!,
      roleByCode.get(b.roleCode)!,
    );
    if (roleCompare !== 0) return roleCompare;
    return comparePermissions(
      permissionByCode.get(a.permissionCode)!,
      permissionByCode.get(b.permissionCode)!,
    );
  });

  const permissionGroups: AdminPermissionGroup[] = [];
  for (const permission of permissions) {
    const last = permissionGroups.at(-1);
    if (!last || last.domain !== permission.domain) {
      permissionGroups.push({
        domain: permission.domain,
        permissions: [permission],
      });
    } else {
      last.permissions.push(permission);
    }
  }

  return {
    state: roles.length === 0 || permissions.length === 0
      ? ("empty" as const)
      : ("ready" as const),
    roles,
    permissionGroups,
    assignments,
    inheritance: {
      supported: false as const,
      reason:
        "The current Command Center RBAC model has direct role-to-permission assignments and no role inheritance graph.",
    },
    elevatedBoundary: {
      enforcement:
        "Permissions with roleAssignable=false are never effective through ordinary role membership, even if a direct database assignment row exists.",
    },
    source: {
      kind: "canonical" as const,
      label: "LifeMate admin RBAC control plane",
      definitionVersion: 1,
    },
  };
}
