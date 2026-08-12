import { ApiError } from "./validation.ts";

export type AdminCapabilitySnapshot = {
  accountId: string;
  roles: string[];
  permissions: string[];
};

export function hasPermission(
  snapshot: AdminCapabilitySnapshot,
  permission: string,
): boolean {
  return snapshot.permissions.includes(permission);
}

export function requirePermission(
  snapshot: AdminCapabilitySnapshot,
  permission: string,
): void {
  if (!hasPermission(snapshot, permission)) {
    throw new ApiError(
      403,
      "admin_permission_denied",
      "Administrative permission is required for this operation.",
    );
  }
}
