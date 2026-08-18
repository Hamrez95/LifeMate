import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  CreateCommercePlanPayload,
  ScheduleCommercePricePayload,
  UpdateCommercePlanPayload,
} from "./commerce_catalog.ts";
import { ApiError } from "./validation.ts";

function mutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "commerce_catalog_workflow_unavailable",
      "Commerce catalog workflow result was unavailable.",
    );
  }
  const row = value as Record<string, unknown>;
  if (
    !Number.isInteger(row.httpStatus) || typeof row.code !== "string" ||
    typeof row.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "commerce_catalog_workflow_unavailable",
      "Commerce catalog workflow result was invalid.",
    );
  }
  return row;
}

export function createCommerceCatalogStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async createPlan(input: {
      actorAccountId: string;
      payload: CreateCommercePlanPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.create_commerce_plan(
          ${input.actorAccountId}::uuid,
          ${p.productId}::uuid,
          ${p.code}::character varying,
          ${p.name}::character varying,
          ${p.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return mutationResult(rows[0]?.result);
    },

    async updatePlan(input: {
      actorAccountId: string;
      planId: string;
      payload: UpdateCommercePlanPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.update_commerce_plan(
          ${input.actorAccountId}::uuid,
          ${input.planId}::uuid,
          ${p.name}::character varying,
          ${p.status}::character varying,
          ${p.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return mutationResult(rows[0]?.result);
    },

    async schedulePrice(input: {
      actorAccountId: string;
      planId: string;
      payload: ScheduleCommercePricePayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.schedule_commerce_price(
          ${input.actorAccountId}::uuid,
          ${input.planId}::uuid,
          ${p.countryCode}::character varying,
          ${p.currency}::character varying,
          ${p.storeProvider}::character varying,
          ${p.billingPeriodMonths}::smallint,
          ${p.amountMinor}::bigint,
          ${p.effectiveFromUtc}::timestamptz,
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
