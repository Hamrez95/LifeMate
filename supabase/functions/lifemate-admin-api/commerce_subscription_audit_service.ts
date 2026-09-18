import { getAdminSql } from "./database_client.ts";

export type CommerceSubscriptionAuditQuery = {
  page: number;
  pageSize: number;
};

type Row = Record<string, unknown>;

function iso(value: unknown): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : String(value);
}

function id(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function integerString(value: unknown): string | null {
  return value == null ? null : String(value);
}

export function createCommerceSubscriptionAuditStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  async function conversions(query: CommerceSubscriptionAuditQuery) {
    const offset = (query.page - 1) * query.pageSize;
    const [rows, totals] = await Promise.all([
      sql`
        select
          c.id,c.source_subscription_id,c.target_subscription_id,c.source_transaction_id,
          sp.code as source_product_code,tp.code as target_product_code,
          c.currency,c.source_net_collected_minor,c.transferable_value_minor,
          c.remaining_seconds,c.service_period_seconds,c.converted_at_utc,
          c.correlation_id,c.idempotency_key
        from commerce.subscription_conversions c
        join commerce.products sp on sp.id=c.source_product_id
        join commerce.products tp on tp.id=c.target_product_id
        order by c.converted_at_utc desc,c.id desc
        limit ${query.pageSize} offset ${offset}
      `,
      sql`select count(*)::integer as total from commerce.subscription_conversions`,
    ]);
    return {
      page: query.page,
      pageSize: query.pageSize,
      total: Number(totals[0]?.total ?? 0),
      items: (rows as unknown as Row[]).map((row) => ({
        conversionId: id(row.id),
        sourceSubscriptionId: id(row.source_subscription_id),
        targetSubscriptionId: id(row.target_subscription_id),
        sourceTransactionId: id(row.source_transaction_id),
        sourceProductCode: String(row.source_product_code ?? ""),
        targetProductCode: String(row.target_product_code ?? ""),
        currency: String(row.currency ?? ""),
        originalPaidMinor: integerString(row.source_net_collected_minor),
        transferredCreditMinor: integerString(row.transferable_value_minor),
        remainingSeconds: integerString(row.remaining_seconds),
        servicePeriodSeconds: integerString(row.service_period_seconds),
        convertedAtUtc: iso(row.converted_at_utc),
        correlationId: id(row.correlation_id),
        idempotencyKey: typeof row.idempotency_key === "string" ? row.idempotency_key : null,
      })),
    };
  }

  async function gifts(query: CommerceSubscriptionAuditQuery) {
    const offset = (query.page - 1) * query.pageSize;
    const [rows, totals] = await Promise.all([
      sql`
        select
          g.id,g.purchaser_account_id,g.recipient_account_id,
          g.target_kind,g.offer_id,g.bundle_id,g.status,g.order_id,g.transaction_id,
          g.price_amount_minor,g.price_currency,g.paid_at_utc,g.claim_expires_at_utc,
          g.claimed_at_utc,g.resulting_subscription_id,g.expires_at_utc,g.fulfilled_at_utc,
          g.version,g.created_at_utc,g.updated_at_utc,
          o.code as offer_code,p.code as product_code
        from commerce.gift_intents g
        left join commerce.offers o on o.id=g.offer_id
        left join commerce.products p on p.id=o.product_id
        order by g.created_at_utc desc,g.id desc
        limit ${query.pageSize} offset ${offset}
      `,
      sql`select count(*)::integer as total from commerce.gift_intents`,
    ]);
    return {
      page: query.page,
      pageSize: query.pageSize,
      total: Number(totals[0]?.total ?? 0),
      items: (rows as unknown as Row[]).map((row) => ({
        giftIntentId: id(row.id),
        purchaserAccountId: id(row.purchaser_account_id),
        recipientAccountId: id(row.recipient_account_id),
        targetKind: String(row.target_kind ?? ""),
        offerId: id(row.offer_id),
        bundleId: id(row.bundle_id),
        offerCode: typeof row.offer_code === "string" ? row.offer_code : null,
        productCode: typeof row.product_code === "string" ? row.product_code : null,
        status: String(row.status ?? ""),
        orderId: id(row.order_id),
        transactionId: id(row.transaction_id),
        priceAmountMinor: integerString(row.price_amount_minor),
        priceCurrency: typeof row.price_currency === "string" ? row.price_currency : null,
        paidAtUtc: iso(row.paid_at_utc),
        claimExpiresAtUtc: iso(row.claim_expires_at_utc),
        claimedAtUtc: iso(row.claimed_at_utc),
        resultingSubscriptionId: id(row.resulting_subscription_id),
        expiresAtUtc: iso(row.expires_at_utc),
        fulfilledAtUtc: iso(row.fulfilled_at_utc),
        version: Number(row.version ?? 0),
        createdAtUtc: iso(row.created_at_utc),
        updatedAtUtc: iso(row.updated_at_utc),
      })),
    };
  }

  return { conversions, gifts };
}
