export type AdminRoleStatus = "Active" | "Disabled";
export type AdminMemberStatus = "Active" | "Disabled" | "Revoked";
export type AdminMembershipState =
  | "active"
  | "scheduled"
  | "expired"
  | "revoked"
  | "member_inactive"
  | "role_disabled";

export type AdminRolePermissionDetail = {
  code: string;
  domain: string;
  riskLevel: "STANDARD" | "SENSITIVE" | "HIGH_RISK" | "ELEVATED";
  roleAssignable: boolean;
  description: string;
  source: "direct";
  effectiveForActiveMember: boolean;
  blockedReason: "role_disabled" | "permission_not_role_assignable" | null;
};

export type AdminMembershipWindow = {
  startsAtUtc: string;
  expiresAtUtc: string | null;
  revokedAtUtc: string | null;
};

export function classifyAdminMembership(
  memberStatus: AdminMemberStatus,
  roleStatus: AdminRoleStatus,
  window: AdminMembershipWindow,
  at: Date,
): AdminMembershipState {
  if (window.revokedAtUtc !== null) return "revoked";

  const startsAt = Date.parse(window.startsAtUtc);
  const expiresAt = window.expiresAtUtc === null
    ? null
    : Date.parse(window.expiresAtUtc);
  if (
    !Number.isFinite(startsAt) ||
    (expiresAt !== null && !Number.isFinite(expiresAt))
  ) {
    throw new Error("admin membership window contains an invalid timestamp");
  }

  const instant = at.getTime();
  if (startsAt > instant) return "scheduled";
  if (expiresAt !== null && expiresAt <= instant) return "expired";
  if (memberStatus !== "Active") return "member_inactive";
  if (roleStatus !== "Active") return "role_disabled";
  return "active";
}

export function rolePermissionDetail(
  roleStatus: AdminRoleStatus,
  permission: Omit<
    AdminRolePermissionDetail,
    "source" | "effectiveForActiveMember" | "blockedReason"
  >,
): AdminRolePermissionDetail {
  const blockedReason = roleStatus !== "Active"
    ? ("role_disabled" as const)
    : !permission.roleAssignable
    ? ("permission_not_role_assignable" as const)
    : null;

  return {
    ...permission,
    source: "direct",
    effectiveForActiveMember: blockedReason === null,
    blockedReason,
  };
}

export function matchAdminRoleDetailPath(path: string): string | null {
  const match = /^\/api\/v1\/security\/roles\/([a-z0-9][a-z0-9._:-]{0,63})$/
    .exec(
      path,
    );
  return match?.[1] ?? null;
}
