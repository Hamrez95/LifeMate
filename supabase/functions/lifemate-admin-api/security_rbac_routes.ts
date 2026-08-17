import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import { createSecurityRbacStore } from "./security_rbac_service.ts";

export type SecurityRbacRouteContext = {
  request: Request;
  path: string;
  admin: AdminCapabilitySnapshot;
  origin: string | null;
};

type SecurityRbacStore = ReturnType<typeof createSecurityRbacStore>;

export function createSecurityRbacRouteHandler(
  databaseUrl: string,
  store: SecurityRbacStore = createSecurityRbacStore(databaseUrl),
) {
  return async function handleSecurityRbacRoute(
    context: SecurityRbacRouteContext,
  ): Promise<Response | null> {
    const { request, path, admin, origin } = context;
    if (
      request.method !== "GET" ||
      path !== "/api/v1/security/role-permission-matrix"
    ) {
      return null;
    }

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
  };
}
