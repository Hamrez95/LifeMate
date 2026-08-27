import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { StaffActionRequest, StaffActionRoute } from "./staff_actions.ts";
import { ApiError } from "./validation.ts";

function result(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "staff_workflow_unavailable",
      "Staff workflow result was unavailable.",
    );
  }
  const parsed = value as Record<string, unknown>;
  if (
    !Number.isInteger(parsed.httpStatus) || typeof parsed.code !== "string" ||
    typeof parsed.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "staff_workflow_unavailable",
      "Staff workflow result was invalid.",
    );
  }
  return parsed;
}

async function requireCustomRoleDelegable(
  sql: AdminSql,
  actorAccountId: string,
  roleCode: string,
): Promise<void> {
  const rows = await sql`
    select
      r.is_system,
      coalesce(
        bool_and(
          p.role_assignable
          and p.risk_level<>'ELEVATED'
          and admin.account_has_permission(${actorAccountId}::uuid,p.code)
        ) filter (where p.code is not null),
        true
      ) as delegable
    from admin.roles r
    left join admin.role_permissions rp on rp.role_id=r.id
    left join admin.permissions p on p.code=rp.permission_code
    where r.code=${roleCode}
    group by r.id
    limit 1
  `;
  if (rows.length === 0 || Boolean(rows[0].is_system)) return;
  if (!Boolean(rows[0].delegable)) {
    throw new ApiError(
      403,
      "permission_delegation_denied",
      "The selected custom role contains permissions outside the actor authority.",
    );
  }
}

export function createStaffActionStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async mutate(input: {
      actorAccountId: string;
      route: StaffActionRoute;
      request: StaffActionRequest;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const {
        actorAccountId,
        route,
        request,
        correlationId,
        idempotencyKey,
        requestHash,
      } = input;
      if (
        route.kind === "role" && route.action === "assign" &&
        request.roleCode !== null
      ) {
        await requireCustomRoleDelegable(sql, actorAccountId, request.roleCode);
      }
      const rows = route.kind === "membership"
        ? await sql`
          select admin.mutate_staff_membership(
            ${actorAccountId}::uuid, ${route.accountId}::uuid,
            ${route.action}::character varying, ${request.reason}::character varying,
            ${correlationId}::uuid, ${idempotencyKey}::character varying,
            ${requestHash}::character varying
          ) as result
        `
        : await sql`
          select admin.mutate_staff_role(
            ${actorAccountId}::uuid, ${route.accountId}::uuid,
            ${request.roleCode}::character varying,
            ${route.action}::character varying, ${request.reason}::character varying,
            ${correlationId}::uuid, ${idempotencyKey}::character varying,
            ${requestHash}::character varying
          ) as result
        `;
      return result(rows[0]?.result);
    },
  };
}
