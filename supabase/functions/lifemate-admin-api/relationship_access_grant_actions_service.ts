import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  AccessGrantAction,
  AccessGrantActionRequest,
} from "./relationship_access_grant_actions.ts";
import { ApiError } from "./validation.ts";

function mutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "access_grant_workflow_unavailable",
      "Access Grant workflow result was unavailable.",
    );
  }
  const parsed = value as Record<string, unknown>;
  if (
    !Number.isInteger(parsed.httpStatus) ||
    typeof parsed.code !== "string" ||
    typeof parsed.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "access_grant_workflow_unavailable",
      "Access Grant workflow result was invalid.",
    );
  }
  return parsed;
}

export function createRelationshipAccessGrantActionStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async mutate(input: {
      actorAccountId: string;
      grantId: string;
      action: AccessGrantAction;
      request: AccessGrantActionRequest;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const {
        actorAccountId,
        grantId,
        action,
        request,
        correlationId,
        idempotencyKey,
        requestHash,
      } = input;
      const rows = await sql`
        select admin.mutate_access_grant(
          ${actorAccountId}::uuid,
          ${grantId}::uuid,
          ${action}::character varying,
          ${request.expectedVersion}::integer,
          ${request.expiresAtUtc}::timestamp with time zone,
          ${request.scopes}::character varying[],
          ${request.reason}::character varying,
          ${correlationId}::uuid,
          ${idempotencyKey}::character varying,
          ${requestHash}::character varying
        ) as result
      `;
      return mutationResult(rows[0]?.result);
    },
  };
}
