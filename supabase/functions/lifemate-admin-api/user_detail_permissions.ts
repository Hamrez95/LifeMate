export type UserDetailSectionPermissions = {
  commerce: boolean;
  relationships: boolean;
  adminActivity: boolean;
};

export function getUserDetailSectionPermissions(
  permissions: readonly string[],
): UserDetailSectionPermissions {
  const allowed = new Set(permissions);
  return {
    commerce: allowed.has("commerce.read"),
    relationships: allowed.has("relationships.read"),
    adminActivity: allowed.has("security.audit.read"),
  };
}
