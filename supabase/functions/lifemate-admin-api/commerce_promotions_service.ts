import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  CommercePromotionsQuery,
  CreatePromotionPayload,
  PromotionStatusPayload,
  UpdatePromotionPayload,
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

function record(value: unknown): Record<string, unknown> {
  return value as Record<string, unknown>;
}

function assertMutationResult(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "promotion_workflow_unavailable",
      "Promotion workflow result was unavailable.",
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
      "promotion_workflow_unavailable",
      "Promotion workflow result was invalid.",
    );
  }
  return row;
}

function maskCode(code: string | null): string | null {
  if (!code) return null;
  if (code.length <= 5) return `${code.slice(0, 1)}…${code.slice(-1)}`;
  return `${code.slice(0, 3)}…${code.slice(-2)}`;
}

async function listProducts(sql: AdminSql) {
  const rows = await sql`
    select id, code, display_name
    from commerce.products
    where status = 'Active'
    order by display_name asc, code asc
    limit 100
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    code: String(row.code),
    name: String(row.display_name),
  }));
}

async function filteredIds(sql: AdminSql, query: CommercePromotionsQuery) {
  return await sql`
    select distinct pr.id
    from commerce.promotions pr
    left join commerce.products product on product.id = pr.product_id
    left join commerce.discount_codes dc on dc.promotion_id = pr.id
    where (${query.product}::text is null or product.code = ${query.product})
      and (
        ${query.status}::text is null
        or case
          when pr.ends_at_utc is not null and pr.ends_at_utc <= now() then 'Expired'
          else pr.status
        end = ${query.status}
      )
      and (${query.q}::text is null or pr.name ilike '%' || ${query.q} || '%')
      and (${query.exactCode}::text is null or lower(dc.code) = lower(${query.exactCode}))
    order by pr.id
  `;
}

async function summary(sql: AdminSql, query: CommercePromotionsQuery) {
  const rows = await sql`
    with filtered as (
      select distinct
        pr.id,
        case
          when pr.ends_at_utc is not null and pr.ends_at_utc <= now() then 'Expired'
          else pr.status
        end as effective_status
      from commerce.promotions pr
      left join commerce.products product on product.id = pr.product_id
      left join commerce.discount_codes dc on dc.promotion_id = pr.id
      where (${query.product}::text is null or product.code = ${query.product})
        and (
          ${query.status}::text is null
          or case
            when pr.ends_at_utc is not null and pr.ends_at_utc <= now() then 'Expired'
            else pr.status
          end = ${query.status}
        )
        and (${query.q}::text is null or pr.name ilike '%' || ${query.q} || '%')
        and (${query.exactCode}::text is null or lower(dc.code) = lower(${query.exactCode}))
    )
    select
      count(*)::integer as total,
      count(*) filter (where effective_status = 'Draft')::integer as draft,
      count(*) filter (where effective_status = 'Active')::integer as active,
      count(*) filter (where effective_status = 'Paused')::integer as paused,
      count(*) filter (where effective_status = 'Expired')::integer as expired
    from filtered
  `;
  const row = record(rows[0] ?? {});
  return {
    total: Number(row.total ?? 0),
    draft: Number(row.draft ?? 0),
    active: Number(row.active ?? 0),
    paused: Number(row.paused ?? 0),
    expired: Number(row.expired ?? 0),
  };
}

async function listPromotions(sql: AdminSql, query: CommercePromotionsQuery) {
  const offset = (query.page - 1) * query.pageSize;
  const rows = await sql`
    with filtered as (
      select distinct pr.id
      from commerce.promotions pr
      left join commerce.products product_filter on product_filter.id = pr.product_id
      left join commerce.discount_codes dc_filter on dc_filter.promotion_id = pr.id
      where (${query.product}::text is null or product_filter.code = ${query.product})
        and (
          ${query.status}::text is null
          or case
            when pr.ends_at_utc is not null and pr.ends_at_utc <= now() then 'Expired'
            else pr.status
          end = ${query.status}
        )
        and (${query.q}::text is null or pr.name ilike '%' || ${query.q} || '%')
        and (${query.exactCode}::text is null or lower(dc_filter.code) = lower(${query.exactCode}))
    ), page as (
      select pr.id
      from filtered f
      join commerce.promotions pr on pr.id = f.id
      order by pr.updated_at_utc desc, pr.id desc
      limit ${query.pageSize}
      offset ${offset}
    )
    select
      pr.id,
      pr.name,
      pr.description,
      pr.discount_type,
      pr.percentage_basis_points,
      pr.fixed_amount_minor,
      pr.currency,
      pr.status as stored_status,
      case
        when pr.ends_at_utc is not null and pr.ends_at_utc <= now() then 'Expired'
        else pr.status
      end as effective_status,
      pr.starts_at_utc,
      pr.ends_at_utc,
      pr.max_redemptions,
      pr.created_at_utc,
      pr.updated_at_utc,
      product.id as product_id,
      product.code as product_code,
      product.display_name as product_name,
      primary_code.code as primary_code,
      primary_code.status as primary_code_status,
      primary_code.max_redemptions as primary_code_max_redemptions,
      (select count(*)::integer from commerce.discount_codes all_codes where all_codes.promotion_id = pr.id) as code_count
    from page
    join commerce.promotions pr on pr.id = page.id
    left join commerce.products product on product.id = pr.product_id
    left join lateral (
      select dc.code, dc.status, dc.max_redemptions
      from commerce.discount_codes dc
      where dc.promotion_id = pr.id
      order by dc.created_at_utc asc, dc.id asc
      limit 1
    ) primary_code on true
    order by pr.updated_at_utc desc, pr.id desc
  `;

  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    promotionId: String(row.id),
    name: String(row.name),
    description: nullableString(row.description),
    product: row.product_id == null ? null : {
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
    storedStatus: String(row.stored_status),
    effectiveStatus: String(row.effective_status),
    startsAtUtc: iso(row.starts_at_utc),
    endsAtUtc: nullableIso(row.ends_at_utc),
    maxRedemptions: nullableNumber(row.max_redemptions),
    primaryCodeMasked: maskCode(nullableString(row.primary_code)),
    primaryCodeStatus: nullableString(row.primary_code_status),
    primaryCodeMaxRedemptions: nullableNumber(row.primary_code_max_redemptions),
    codeCount: Number(row.code_count ?? 0),
    redemptionSummary: {
      state: "unavailable" as const,
      count: null,
      reason:
        "Redemption source is not instrumented in the canonical Commerce ledger yet.",
    },
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  }));
}

async function getPromotion(sql: AdminSql, promotionId: string) {
  const rows = await sql`
    select
      pr.id,
      pr.name,
      pr.description,
      pr.discount_type,
      pr.percentage_basis_points,
      pr.fixed_amount_minor,
      pr.currency,
      pr.status as stored_status,
      case
        when pr.ends_at_utc is not null and pr.ends_at_utc <= now() then 'Expired'
        else pr.status
      end as effective_status,
      pr.starts_at_utc,
      pr.ends_at_utc,
      pr.max_redemptions,
      pr.created_at_utc,
      pr.updated_at_utc,
      product.id as product_id,
      product.code as product_code,
      product.display_name as product_name
    from commerce.promotions pr
    left join commerce.products product on product.id = pr.product_id
    where pr.id = ${promotionId}::uuid
    limit 1
  `;
  if (rows.length === 0) return null;
  const row = record(rows[0]);
  return {
    promotionId: String(row.id),
    name: String(row.name),
    description: nullableString(row.description),
    product: row.product_id == null ? null : {
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
    storedStatus: String(row.stored_status),
    effectiveStatus: String(row.effective_status),
    startsAtUtc: iso(row.starts_at_utc),
    endsAtUtc: nullableIso(row.ends_at_utc),
    maxRedemptions: nullableNumber(row.max_redemptions),
    redemptionSummary: {
      state: "unavailable" as const,
      count: null,
      reason:
        "Redemption source is not instrumented in the canonical Commerce ledger yet.",
    },
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

async function listCodes(sql: AdminSql, promotionId: string) {
  const rows = await sql`
    select id, code, status, max_redemptions, created_at_utc, updated_at_utc
    from commerce.discount_codes
    where promotion_id = ${promotionId}::uuid
    order by created_at_utc asc, id asc
    limit 100
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    codeId: String(row.id),
    code: String(row.code),
    status: String(row.status),
    maxRedemptions: nullableNumber(row.max_redemptions),
    redemptionSummary: {
      state: "unavailable" as const,
      count: null,
      reason:
        "Redemption source is not instrumented in the canonical Commerce ledger yet.",
    },
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  }));
}

async function listAuditEvents(sql: AdminSql, promotionId: string) {
  const rows = await sql`
    select
      id,
      action,
      result,
      reason,
      correlation_id,
      actor_account_id is not null as actor_linked,
      occurred_at_utc
    from admin.audit_events
    where resource_type = 'commerce_promotion'
      and resource_id = ${promotionId}
      and action like 'commerce.promotion.%'
    order by occurred_at_utc desc, id desc
    limit 100
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    auditEventId: String(row.id),
    action: String(row.action),
    result: String(row.result),
    reason: nullableString(row.reason),
    correlationId: String(row.correlation_id),
    actorLinked: Boolean(row.actor_linked),
    occurredAtUtc: iso(row.occurred_at_utc),
  }));
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
      return {
        products,
        summary: counts,
        items,
        total: counts.total,
      };
    },

    async getDetail(promotionId: string, includeAudit: boolean) {
      const promotion = await getPromotion(sql, promotionId);
      if (!promotion) return null;
      const [codes, auditEvents] = await Promise.all([
        listCodes(sql, promotionId),
        includeAudit
          ? listAuditEvents(sql, promotionId)
          : Promise.resolve(null),
      ]);
      return {
        promotion,
        codes,
        auditEvidence: includeAudit
          ? { state: "ready" as const, items: auditEvents ?? [] }
          : { state: "forbidden" as const },
      };
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

    async update(input: {
      actorAccountId: string;
      promotionId: string;
      payload: UpdatePromotionPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.update_commerce_promotion(
          ${input.actorAccountId}::uuid,
          ${input.promotionId}::uuid,
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
          ${p.codeStatus}::text,
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
