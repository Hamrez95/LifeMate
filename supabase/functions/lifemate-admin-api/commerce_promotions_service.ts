import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  CommercePromotionsQuery,
  CreatePromotionPayload,
  PromotionStatusPayload,
} from "./commerce_promotions.ts";
import { ApiError } from "./validation.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function nullableIso(value: unknown): string | null {
  return value == null ? null : iso(value);
}

function nullableString(value: unknown): string | null {
  return value == null ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  return value == null ? null : Number(value);
}

function assertMutationResult(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(503, "promotion_workflow_unavailable", "Promotion workflow result was unavailable.");
  }
  const row = value as Record<string, unknown>;
  if (!Number.isInteger(row.httpStatus) || typeof row.code !== "string" || typeof row.replayed !== "boolean") {
    throw new ApiError(503, "promotion_workflow_unavailable", "Promotion workflow result was invalid.");
  }
  return row;
}

async function listProducts(sql: AdminSql) {
  const rows = await sql`
    select id, code, display_name
    from commerce.products
    where is_active = true
    order by display_name asc, code asc
    limit 100
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    code: String(row.code),
    name: String(row.display_name),
  }));
}

async function summary(sql: AdminSql, query: CommercePromotionsQuery) {
  const rows = await sql`
    with filtered as (
      select distinct pr.id, pr.status
      from commerce.promotions pr
      left join commerce.products product on product.id = pr.product_id
      left join commerce.discount_codes dc on dc.promotion_id = pr.id
      where (${query.product}::text is null or product.code = ${query.product})
        and (${query.status}::text is null or pr.status = ${query.status})
        and (
          ${query.q}::text is null
          or pr.name ilike '%' || ${query.q} || '%'
          or dc.code ilike '%' || ${query.q} || '%'
        )
    )
    select
      count(*)::integer as total,
      count(*) filter (where status = 'Draft')::integer as draft,
      count(*) filter (where status = 'Active')::integer as active,
      count(*) filter (where status = 'Paused')::integer as paused,
      count(*) filter (where status = 'Expired')::integer as expired
    from filtered
  `;
  const row = rows[0] as Record<string, unknown> | undefined;
  return {
    total: Number(row?.total ?? 0),
    draft: Number(row?.draft ?? 0),
    active: Number(row?.active ?? 0),
    paused: Number(row?.paused ?? 0),
    expired: Number(row?.expired ?? 0),
  };
}

async function listPromotions(sql: AdminSql, query: CommercePromotionsQuery) {
  const offset = (query.page - 1) * query.pageSize;
  const rows = await sql`
    with filtered as (
      select distinct pr.id
      from commerce.promotions pr
      left join commerce.products product on product.id = pr.product_id
      left join commerce.discount_codes dc on dc.promotion_id = pr.id
      where (${query.product}::text is null or product.code = ${query.product})
        and (${query.status}::text is null or pr.status = ${query.status})
        and (
          ${query.q}::text is null
          or pr.name ilike '%' || ${query.q} || '%'
          or dc.code ilike '%' || ${query.q} || '%'
        )
    )
    select
      pr.id,
      pr.name,
      pr.description,
      pr.discount_type,
      pr.percentage_basis_points,
      pr.fixed_amount_minor,
      pr.currency,
      pr.status,
      pr.starts_at_utc,
      pr.ends_at_utc,
      pr.max_redemptions,
      pr.created_at_utc,
      pr.updated_at_utc,
      product.id as product_id,
      product.code as product_code,
      product.display_name as product_name,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'codeId', dc.id,
            'code', dc.code,
            'status', dc.status,
            'maxRedemptions', dc.max_redemptions,
            'redemptionCount', dc.redemption_count,
            'createdAtUtc', dc.created_at_utc,
            'updatedAtUtc', dc.updated_at_utc
          ) order by dc.created_at_utc asc, dc.id asc
        ) filter (where dc.id is not null),
        '[]'::jsonb
      ) as codes
    from filtered f
    join commerce.promotions pr on pr.id = f.id
    left join commerce.products product on product.id = pr.product_id
    left join commerce.discount_codes dc on dc.promotion_id = pr.id
    group by pr.id, product.id, product.code, product.display_name
    order by pr.updated_at_utc desc, pr.id desc
    limit ${query.pageSize}
    offset ${offset}
  `;

  return (rows as unknown as Record<string, unknown>[]).map((row) => {
    const codes = Array.isArray(row.codes) ? row.codes : [];
    return {
      promotionId: String(row.id),
      name: String(row.name),
      description: nullableString(row.description),
      product: row.product_id == null
        ? null
        : {
          id: String(row.product_id),
          code: String(row.product_code),
          name: String(row.product_name),
        },
      discount: {
        type: String(row.discount_type),
        percentageBasisPoints: nullableNumber(row.percentage_basis_points),
        fixedAmountMinor: nullableString(row.fixed_amount_minor),
        currency: nullableString(row.currency),
      },
      status: String(row.status),
      startsAtUtc: iso(row.starts_at_utc),
      endsAtUtc: nullableIso(row.ends_at_utc),
      maxRedemptions: nullableNumber(row.max_redemptions),
      createdAtUtc: iso(row.created_at_utc),
      updatedAtUtc: iso(row.updated_at_utc),
      codes: (codes as Record<string, unknown>[]).map((code) => ({
        codeId: String(code.codeId),
        code: String(code.code),
        status: String(code.status),
        maxRedemptions: nullableNumber(code.maxRedemptions),
        redemptionCount: Number(code.redemptionCount ?? 0),
        createdAtUtc: iso(code.createdAtUtc),
        updatedAtUtc: iso(code.updatedAtUtc),
      })),
    };
  });
}

export function createCommercePromotionsStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async list(query: CommercePromotionsQuery) {
      const [products, counts, items] = await Promise.all([
        listProducts(sql),
        summary(sql, query),
        listPromotions(sql, query),
      ]);
      return { products, summary: counts, items };
    },

    async create(input: {
      actorAccountId: string;
      payload: CreatePromotionPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.create_commerce_promotion(
          ${input.actorAccountId}::uuid,
          ${p.productId}::uuid,
          ${p.name}::character varying,
          ${p.description}::character varying,
          ${p.discountType}::text,
          ${p.percentageBasisPoints}::integer,
          ${p.fixedAmountMinor}::bigint,
          ${p.currency}::text,
          ${p.startsAtUtc}::timestamptz,
          ${p.endsAtUtc}::timestamptz,
          ${p.maxRedemptions}::integer,
          ${p.primaryCode}::character varying,
          ${p.codeMaxRedemptions}::integer,
          ${p.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },

    async setStatus(input: {
      actorAccountId: string;
      promotionId: string;
      payload: PromotionStatusPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.set_commerce_promotion_status(
          ${input.actorAccountId}::uuid,
          ${input.promotionId}::uuid,
          ${input.payload.status}::text,
          ${input.payload.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },
  };
}
