import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  DiscountCodeStatusPayload,
  IssueDiscountCodesPayload,
} from "./commerce_promotions.ts";
import { ApiError } from "./validation.ts";

function assertMutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "discount_code_workflow_unavailable",
      "Discount-code workflow result was unavailable.",
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
      "discount_code_workflow_unavailable",
      "Discount-code workflow result was invalid.",
    );
  }
  return row;
}

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

export function createCommerceDiscountCodeStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async list(promotionId: string) {
      const rows = await sql`
        select id, code, status, max_redemptions, version, created_at_utc, updated_at_utc
        from commerce.discount_codes
        where promotion_id = ${promotionId}::uuid
        order by created_at_utc asc, id asc
        limit 100
      `;
      return (rows as unknown as Record<string, unknown>[]).map((row) => ({
        codeId: String(row.id),
        code: String(row.code),
        status: String(row.status),
        maxRedemptions: row.max_redemptions == null
          ? null
          : Number(row.max_redemptions),
        version: Number(row.version),
        createdAtUtc: iso(row.created_at_utc),
        updatedAtUtc: iso(row.updated_at_utc),
      }));
    },

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
