import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { ConfigureCommerceTrialPayload } from "./commerce_trial.ts";
import { ApiError } from "./validation.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

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
    !Number.isInteger(row.httpStatus) ||
    typeof row.code !== "string" ||
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
    async get(planId: string) {
      const rows = await sql`
        select *
        from admin.get_commerce_trial_policy(${planId}::uuid)
      `;
      const value = rows[0] as Record<string, unknown> | undefined;
      if (!value) return null;
      return {
        planId: String(value.plan_id),
        durationDays: Number(value.duration_days),
        eligibilityRule: String(value.eligibility_rule),
        status: String(value.status),
        version: Number(value.version),
        createdAtUtc: iso(value.created_at_utc),
        updatedAtUtc: iso(value.updated_at_utc),
      };
    },

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
