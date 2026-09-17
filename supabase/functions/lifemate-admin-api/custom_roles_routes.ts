import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  hashCustomRoleMutationRequest,
  hashCustomRolePermissionRequest,
  matchCustomRolePath,
  matchCustomRolePermissionPath,
  matchCustomRoleRetirePath,
  parseCustomRoleMutationRequest,
  parseCustomRolePermissionRequest,
} from "./custom_roles.ts";
import { createCustomRoleStore } from "./custom_roles_service.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  admin: AdminCapabilitySnapshot;
  accountId: string;
  correlationId: string;
  origin: string | null;
};

function status(result: Record<string, unknown>): number {
  const value = Number(result.httpStatus);
  if (!Number.isInteger(value) || value < 100 || value > 599) {
    throw new ApiError(
      503,
      "custom_role_workflow_unavailable",
      "Custom role workflow returned an invalid status.",
    );
  }
  return value;
}

function requireSuccess(result: Record<string, unknown>): number {
  const httpStatus = status(result);
  if (httpStatus >= 400) {
    throw new ApiError(
      httpStatus,
      String(result.code),
      typeof result.message === "string"
        ? result.message
        : "Custom role mutation was not completed.",
    );
  }
  return httpStatus;
}

export function createCustomRoleRouteHandler(databaseUrl: string) {
  const store = createCustomRoleStore(databaseUrl);
  return async function handleCustomRoleRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, admin, accountId, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/security/custom-roles") {
      requirePermission(admin, "security.audit.read");
      const data = await store.list(accountId);
      return json(
        {
          ...data,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "POST" && path === "/api/v1/security/custom-roles") {
      requirePermission(admin, "security.roles.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCustomRoleMutationRequest(request, "create");
      const result = await store.mutateRole({
        actorAccountId: accountId,
        action: "create",
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashCustomRoleMutationRequest("create", payload),
      });
      return json(result, requireSuccess(result), origin);
    }

    const retireCode = matchCustomRoleRetirePath(path);
    if (request.method === "POST" && retireCode) {
      requirePermission(admin, "security.roles.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCustomRoleMutationRequest(
        request,
        "retire",
        retireCode,
      );
      const result = await store.mutateRole({
        actorAccountId: accountId,
        action: "retire",
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashCustomRoleMutationRequest("retire", payload),
      });
      return json(result, requireSuccess(result), origin);
    }

    const permissionRoute = matchCustomRolePermissionPath(path);
    if (request.method === "POST" && permissionRoute) {
      requirePermission(admin, "security.roles.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCustomRolePermissionRequest(request);
      const result = await store.mutatePermission({
        actorAccountId: accountId,
        roleCode: permissionRoute.roleCode,
        action: permissionRoute.action,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashCustomRolePermissionRequest(
          permissionRoute.roleCode,
          permissionRoute.action,
          payload,
        ),
      });
      return json(result, requireSuccess(result), origin);
    }

    const roleCode = matchCustomRolePath(path);
    if (request.method === "PUT" && roleCode) {
      requirePermission(admin, "security.roles.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCustomRoleMutationRequest(
        request,
        "update",
        roleCode,
      );
      const result = await store.mutateRole({
        actorAccountId: accountId,
        action: "update",
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashCustomRoleMutationRequest("update", payload),
      });
      return json(result, requireSuccess(result), origin);
    }

    return null;
  };
}
