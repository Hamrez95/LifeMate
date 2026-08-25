import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { ConfigureCommercePlanFeaturePayload } from "./commerce_plan_features.ts";
import { ApiError } from "./validation.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function mutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "commerce_plan_feature_workflow_unavailable",
      "Plan feature workflow result was unavailable.",
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
      "commerce_plan_feature_workflow_unavailable",
      "Plan feature workflow result was invalid.",
    );
  }
  return row;
}

export function createCommercePlanFeatureStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async list(planId: string) {
      const rows = await sql`
        select *
        from admin.get_commerce_plan_features(${planId}::uuid)
      `;
      return (rows as unknown as Record<string, unknown>[]).map((value) => ({
        featureId: String(value.feature_id),
        featureCode: String(value.feature_code),
        description: String(value.description),
        assigned: Boolean(value.assigned),
        version: Number(value.version),
        updatedAtUtc: value.updated_at_utc == null
          ? null
          : iso(value.updated_at_utc),
      }));
    },

    async configure(input: {
      actorAccountId: string;
      planId: string;
      payload: ConfigureCommercePlanFeaturePayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.configure_commerce_plan_feature(
          ${input.actorAccountId}::uuid,
          ${input.planId}::uuid,
          ${p.featureId}::uuid,
          ${p.assigned}::boolean,
          ${p.expectedVersion}::integer,
          ${p.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return mutationResult(rows[0]?.result);
    },
  };
}
