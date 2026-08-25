import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  DiscountCodeStatusPayload,
  IssueDiscountCodesPayload,
} from "./commerce_promotions.ts";
import { ApiError } from "./validation.ts";

function assertMutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(503, "discount_code_workflow_unavailable", "Discount-code workflow result was unavailable.");
  }
  const row = value as Record<string, unknown>;
  if (!Number.isInteger(row.httpStatus) || typeof row.code !== "string" || typeof row.replayed !== "boolean") {
    throw new ApiError(503, "discount_code_workflow_unavailable", "Discount-code workflow result was invalid.");
  }
  return row;
}

export function createCommerceDiscountCodeStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async issue(input: {
      actorAccountId: string;
      promotionId: string;
      payload: IssueDiscountCodesPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.issue_commerce_discount_codes(
          ${input.actorAccountId}::uuid,
          ${input.promotionId}::uuid,
          ${p.explicitCodes}::varchar[],
          ${p.generateCount}::smallint,
          ${p.prefix}::varchar,
          ${p.maxRedemptions}::integer,
          ${p.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },

    async setStatus(input: {
      actorAccountId: string;
      promotionId: string;
      codeId: string;
      payload: DiscountCodeStatusPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.set_commerce_discount_code_status(
          ${input.actorAccountId}::uuid,
          ${input.promotionId}::uuid,
          ${input.codeId}::uuid,
          ${p.status}::varchar,
          ${p.expectedVersion}::integer,
          ${p.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },
  };
}
