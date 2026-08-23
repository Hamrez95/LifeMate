import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { ConfigureCommerceTrialPayload } from "./commerce_trial.ts";
import { ApiError } from "./validation.ts";

function mutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "commerce_trial_workflow_unavailable",
      "Trial workflow result was unavailable.",
    );
  }
  const row = value as Record<string, unknown>;
  if (
    !Number.isInteger(row.httpStatus) || typeof row.code !== "string" ||
    typeof row.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "commerce_trial_workflow_unavailable",
      "Trial workflow result was invalid.",
    );
  }
  return row;
}

export function createCommerceTrialStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async configure(input: {
      actorAccountId: string;
      planId: string;
      payload: ConfigureCommerceTrialPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.configure_commerce_trial_policy(
          ${input.actorAccountId}::uuid, ${input.planId}::uuid,
          ${p.durationDays}::smallint, ${p.eligibilityRule}::character varying,
          ${p.status}::character varying,
          ${p.expectedVersion}::integer, ${p.reason}::character varying,
          ${input.correlationId}::uuid, ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return mutationResult(rows[0]?.result);
    },
  };
}
