import { createApprovalRequestRouteHandler } from "./approval_requests_routes.ts";
import { createAbuseRuleRouteHandler } from "./abuse_rules_routes.ts";
import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { createBreakGlassRouteHandler } from "./break_glass_routes.ts";
import { createCustomRoleRouteHandler } from "./custom_roles_routes.ts";
import { createElevatedHealthRouteHandler } from "./elevated_health_routes.ts";
import { json } from "./http.ts";
import { createRetentionRouteHandler } from "./retention_routes.ts";
import { createSecurityRbacStore } from "./security_rbac_service.ts";
import { matchAdminRoleDetailPath } from "./security_role_detail.ts";
import { createSecurityRoleDetailStore } from "./security_role_detail_service.ts";
import { ApiError } from "./validation.ts";

export type SecurityRbacRouteContext = {
  request: Request;
  path: string;
  admin: AdminCapabilitySnapshot;
  origin: string | null;
  accountId?: string;
  correlationId?: string;
};

type SecurityRbacStore = ReturnType<typeof createSecurityRbacStore>;
type SecurityRoleDetailStore = ReturnType<typeof createSecurityRoleDetailStore>;

export function createSecurityRbacRouteHandler(
  databaseUrl: string,
  store: SecurityRbacStore = createSecurityRbacStore(databaseUrl),
  roleDetailStore?: SecurityRoleDetailStore,
) {
  let resolvedRoleDetailStore = roleDetailStore;
  const breakGlassRouteHandler = createBreakGlassRouteHandler(databaseUrl);
  const elevatedHealthRouteHandler = createElevatedHealthRouteHandler(
    databaseUrl,
  );
  const customRoleRouteHandler = createCustomRoleRouteHandler(databaseUrl);
  const approvalRequestRouteHandler = createApprovalRequestRouteHandler(
    databaseUrl,
  );
  const retentionRouteHandler = createRetentionRouteHandler(databaseUrl);
  const abuseRuleRouteHandler = createAbuseRuleRouteHandler(databaseUrl);

  return async function handleSecurityRbacRoute(
    context: SecurityRbacRouteContext,
  ): Promise<Response | null> {
    const { request, path, admin, origin } = context;
    const accountId = context.accountId ?? admin.accountId;
    const correlationId = context.correlationId ?? crypto.randomUUID();

    if (path.startsWith("/api/v1/operations/approval-requests")) {
      const response = await approvalRequestRouteHandler({
        request,
        path,
        accountId,
        admin,
        correlationId,
        origin,
      });
      if (response) return response;
    }

    if (path.startsWith("/api/v1/security/retention/")) {
      const response = await retentionRouteHandler({
        request,
        path,
        accountId,
        admin,
        correlationId,
        origin,
      });
      if (response) return response;
    }

    if (path.startsWith("/api/v1/security/abuse/")) {
      const response = await abuseRuleRouteHandler({
        request,
        path,
        accountId,
        admin,
        correlationId,
        origin,
      });
      if (response) return response;
    }

    if (path.startsWith("/api/v1/security/break-glass/")) {
      const response = await breakGlassRouteHandler({
        request,
        path,
        accountId,
        admin,
        correlationId,
        origin,
      });
      if (response) return response;
    }

    if (path.startsWith("/api/v1/security/elevated-health/")) {
      const response = await elevatedHealthRouteHandler({
        request,
        path,
        accountId,
        admin,
        correlationId,
        origin,
      });
      if (response) return response;
    }

    if (path.startsWith("/api/v1/security/custom-roles")) {
      const response = await customRoleRouteHandler({
        request,
        path,
        accountId,
        admin,
        correlationId,
        origin,
      });
      if (response) return response;
    }

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
