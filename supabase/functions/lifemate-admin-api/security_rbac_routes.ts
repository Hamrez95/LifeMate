import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import { createSecurityRbacStore } from "./security_rbac_service.ts";
import { matchAdminRoleDetailPath } from "./security_role_detail.ts";
import { createSecurityRoleDetailStore } from "./security_role_detail_service.ts";
import { ApiError } from "./validation.ts";

export type SecurityRbacRouteContext = {
  request: Request;
  path: string;
  admin: AdminCapabilitySnapshot;
  origin: string | null;
};

type SecurityRbacStore = ReturnType<typeof createSecurityRbacStore>;
type SecurityRoleDetailStore = ReturnType<typeof createSecurityRoleDetailStore>;

export function createSecurityRbacRouteHandler(
  databaseUrl: string,
  store: SecurityRbacStore = createSecurityRbacStore(databaseUrl),
  roleDetailStore?: SecurityRoleDetailStore,
) {
  let resolvedRoleDetailStore = roleDetailStore;

  return async function handleSecurityRbacRoute(
    context: SecurityRbacRouteContext,
  ): Promise<Response | null> {
    const { request, path, admin, origin } = context;
    if (request.method !== "GET") return null;

    if (path === "/api/v1/security/role-permission-matrix") {
      requirePermission(admin, "security.audit.read");
      const matrix = await store.getRolePermissionMatrix();
      return json(
        {
          ...matrix,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const roleCode = matchAdminRoleDetailPath(path);
    if (roleCode) {
      requirePermission(admin, "security.audit.read");
      resolvedRoleDetailStore ??= createSecurityRoleDetailStore(databaseUrl);
      const detail = await resolvedRoleDetailStore.getRoleDetail(roleCode);
      if (!detail) {
        throw new ApiError(
          404,
          "security_role_not_found",
          "The requested administrative role does not exist.",
        );
      }
      return json(
        {
          ...detail,
          freshness: {
            status: "fresh",
            asOfUtc: detail.evaluationAtUtc,
          },
        },
        200,
        origin,
      );
    }

    return null;
  };
}
