import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { CommerceTransactionsQuery } from "./commerce_transactions.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function nullableString(value: unknown): string | null {
  return value == null ? null : String(value);
}

export function mapCommerceTransactionRow(row: Record<string, unknown>) {
  return {
    transactionId: String(row.transaction_id),
    orderId: nullableString(row.order_id),
    subscriptionId: nullableString(row.subscription_id),
    accountLinked: Boolean(row.account_linked),
    productCode: String(row.product_code),
    productName: String(row.product_name),
    provider: String(row.provider),
    providerStatus: String(row.provider_status),
    normalizedStatus: String(row.normalized_status),
    amountMinor: String(row.amount_minor),
    currency: String(row.currency),
    occurredAtUtc: iso(row.occurred_at_utc),
    receivedAtUtc: iso(row.received_at_utc),
    observationState: nullableString(row.observation_state) ?? "NoEvent",
    latestEventOccurredAtUtc: row.latest_event_occurred_at_utc == null
      ? null
      : iso(row.latest_event_occurred_at_utc),
    latestEventReceivedAtUtc: row.latest_event_received_at_utc == null
      ? null
      : iso(row.latest_event_received_at_utc),
  };
}

async function listProducts(sql: AdminSql) {
  const rows = await sql`
    select id, code, display_name
    from commerce.products
    order by display_name asc, code asc
    limit 100
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    code: String(row.code),
    name: String(row.display_name),
  }));
}

async function listProviders(sql: AdminSql) {
  const rows = await sql`
    select distinct provider
    from commerce.transactions
    order by provider asc
    limit 100
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) =>
    String(row.provider)
  );
}

async function getSummary(sql: AdminSql, query: CommerceTransactionsQuery) {
  const rows = await sql`
    select
      count(*)::integer as total,
      count(*) filter (where t.normalized_status = 'Pending')::integer as pending,
      count(*) filter (where t.normalized_status = 'Succeeded')::integer as succeeded,
      count(*) filter (where t.normalized_status = 'Failed')::integer as failed,
      count(*) filter (where t.normalized_status = 'Cancelled')::integer as cancelled,
      count(*) filter (where t.normalized_status = 'Refunded')::integer as refunded,
      count(*) filter (where t.normalized_status = 'Chargeback')::integer as chargeback
    from commerce.transactions t
    join commerce.products p on p.id = t.product_id
    where (${query.product}::text is null or p.code = ${query.product})
      and (${query.provider}::text is null or t.provider = ${query.provider})
      and (${query.status}::text is null or t.normalized_status = ${query.status})
      and (${query.fromUtc}::timestamptz is null or t.received_at_utc >= ${query.fromUtc}::timestamptz)
      and (${query.toUtc}::timestamptz is null or t.received_at_utc <= ${query.toUtc}::timestamptz)
      and (
        ${query.referenceId}::uuid is null
        or t.id = ${query.referenceId}::uuid
        or t.order_id = ${query.referenceId}::uuid
        or t.subscription_id = ${query.referenceId}::uuid
      )
  `;
  const row = (rows[0] ?? {}) as Record<string, unknown>;
  return {
    total: Number(row.total ?? 0),
    pending: Number(row.pending ?? 0),
    succeeded: Number(row.succeeded ?? 0),
    failed: Number(row.failed ?? 0),
    cancelled: Number(row.cancelled ?? 0),
    refunded: Number(row.refunded ?? 0),
    chargeback: Number(row.chargeback ?? 0),
  };
}

async function getAnomalySummary(
  sql: AdminSql,
  query: CommerceTransactionsQuery,
) {
  const rows = await sql`
    select
      count(*) filter (where ev.observation_state = 'Duplicate')::integer as duplicate,
      count(*) filter (where ev.observation_state = 'OutOfOrder')::integer as out_of_order
    from commerce.transaction_events ev
    join commerce.transactions t on t.id = ev.transaction_id
    join commerce.products p on p.id = t.product_id
    where (${query.product}::text is null or p.code = ${query.product})
      and (${query.provider}::text is null or t.provider = ${query.provider})
      and (${query.status}::text is null or t.normalized_status = ${query.status})
      and (${query.fromUtc}::timestamptz is null or t.received_at_utc >= ${query.fromUtc}::timestamptz)
      and (${query.toUtc}::timestamptz is null or t.received_at_utc <= ${query.toUtc}::timestamptz)
      and (
        ${query.referenceId}::uuid is null
        or t.id = ${query.referenceId}::uuid
        or t.order_id = ${query.referenceId}::uuid
        or t.subscription_id = ${query.referenceId}::uuid
      )
  `;
  const row = (rows[0] ?? {}) as Record<string, unknown>;
  return {
    duplicateEvents: Number(row.duplicate ?? 0),
    outOfOrderEvents: Number(row.out_of_order ?? 0),
  };
}

async function listTransactions(
  sql: AdminSql,
  query: CommerceTransactionsQuery,
) {
  const rows = await sql`
    select
      t.id as transaction_id,
      t.order_id,
      t.subscription_id,
      t.account_id is not null as account_linked,
      p.code as product_code,
      p.display_name as product_name,
      t.provider,
      t.provider_status,
      t.normalized_status,
      t.amount_minor,
      t.currency,
      t.occurred_at_utc,
      t.received_at_utc,
      latest_event.observation_state,
      latest_event.occurred_at_utc as latest_event_occurred_at_utc,
      latest_event.received_at_utc as latest_event_received_at_utc
    from commerce.transactions t
    join commerce.products p on p.id = t.product_id
    left join lateral (
      select ev.observation_state, ev.occurred_at_utc, ev.received_at_utc
      from commerce.transaction_events ev
      where ev.transaction_id = t.id
      order by ev.received_at_utc desc, ev.id desc
      limit 1
    ) latest_event on true
    where (${query.product}::text is null or p.code = ${query.product})
      and (${query.provider}::text is null or t.provider = ${query.provider})
      and (${query.status}::text is null or t.normalized_status = ${query.status})
      and (${query.fromUtc}::timestamptz is null or t.received_at_utc >= ${query.fromUtc}::timestamptz)
      and (${query.toUtc}::timestamptz is null or t.received_at_utc <= ${query.toUtc}::timestamptz)
      and (
        ${query.referenceId}::uuid is null
        or t.id = ${query.referenceId}::uuid
        or t.order_id = ${query.referenceId}::uuid
        or t.subscription_id = ${query.referenceId}::uuid
      )
    order by t.received_at_utc desc, t.id desc
    limit ${query.pageSize} offset ${query.offset}
  `;

  return (rows as unknown as Record<string, unknown>[]).map(
    mapCommerceTransactionRow,
  );
}

async function listRecentOrders(sql: AdminSql, query: CommerceTransactionsQuery) {
  const countRows = await sql`
    select count(*)::integer as total
    from commerce.orders o
    join commerce.products p on p.id = o.product_id
    where (${query.product}::text is null or p.code = ${query.product})
      and (${query.fromUtc}::timestamptz is null or o.occurred_at_utc >= ${query.fromUtc}::timestamptz)
      and (${query.toUtc}::timestamptz is null or o.occurred_at_utc <= ${query.toUtc}::timestamptz)
      and (
        ${query.referenceId}::uuid is null
        or o.id = ${query.referenceId}::uuid
        or o.subscription_id = ${query.referenceId}::uuid
      )
  `;
  const rows = await sql`
    select
      o.id as order_id,
      o.subscription_id,
      p.code as product_code,
      p.display_name as product_name,
      o.status,
      o.amount_minor,
      o.currency,
      o.occurred_at_utc,
      o.updated_at_utc,
      exists (
        select 1 from commerce.transactions t where t.order_id = o.id
      ) as has_transaction
    from commerce.orders o
    join commerce.products p on p.id = o.product_id
    where (${query.product}::text is null or p.code = ${query.product})
      and (${query.fromUtc}::timestamptz is null or o.occurred_at_utc >= ${query.fromUtc}::timestamptz)
      and (${query.toUtc}::timestamptz is null or o.occurred_at_utc <= ${query.toUtc}::timestamptz)
      and (
        ${query.referenceId}::uuid is null
        or o.id = ${query.referenceId}::uuid
        or o.subscription_id = ${query.referenceId}::uuid
      )
    order by o.updated_at_utc desc, o.id desc
    limit 12
  `;
  return {
    total: Number(countRows[0]?.total ?? 0),
    items: (rows as unknown as Record<string, unknown>[]).map((row) => ({
      orderId: String(row.order_id),
      subscriptionId: nullableString(row.subscription_id),
      productCode: String(row.product_code),
      productName: String(row.product_name),
      status: String(row.status),
      amountMinor: String(row.amount_minor),
      currency: String(row.currency),
      occurredAtUtc: iso(row.occurred_at_utc),
      updatedAtUtc: iso(row.updated_at_utc),
      hasTransaction: Boolean(row.has_transaction),
    })),
  };
}

export function createCommerceTransactionsStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async list(query: CommerceTransactionsQuery) {
      const [
        summary,
        anomalies,
        transactions,
        recentOrders,
        products,
        providers,
      ] = await Promise.all([
        getSummary(sql, query),
        getAnomalySummary(sql, query),
        listTransactions(sql, query),
        listRecentOrders(sql, query),
        listProducts(sql),
        listProviders(sql),
      ]);
      return {
        summary,
        anomalies,
        transactions: { items: transactions, total: summary.total },
        recentOrders,
        products,
        providers,
      };
    },
  };
}
