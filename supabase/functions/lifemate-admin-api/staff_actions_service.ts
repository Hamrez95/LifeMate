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
