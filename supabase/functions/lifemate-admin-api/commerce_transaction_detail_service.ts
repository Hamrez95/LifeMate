import { type AdminSql, getAdminSql } from "./database_client.ts";
import { assertCommerceRefundRequestResult } from "./commerce_transaction_detail.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function nullableIso(value: unknown): string | null {
  return value == null ? null : iso(value);
}

function nullableString(value: unknown): string | null {
  return value == null ? null : String(value);
}

function record(value: unknown): Record<string, unknown> {
  return value as Record<string, unknown>;
}

export function mapCommerceTransactionDetailRow(row: Record<string, unknown>) {
  return {
    transactionId: String(row.transaction_id),
    orderId: nullableString(row.order_id),
    subscriptionId: nullableString(row.subscription_id),
    accountLinked: Boolean(row.account_linked),
    product: {
      code: String(row.product_code),
      name: String(row.product_name),
    },
    provider: String(row.provider),
    providerStatus: String(row.provider_status),
    normalizedStatus: String(row.normalized_status),
    amountMinor: String(row.amount_minor),
    currency: String(row.currency),
    occurredAtUtc: iso(row.occurred_at_utc),
    receivedAtUtc: iso(row.received_at_utc),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
    order: row.order_id == null
      ? null
      : {
        orderId: String(row.order_id),
        status: String(row.order_status),
        amountMinor: String(row.order_amount_minor),
        currency: String(row.order_currency),
        occurredAtUtc: iso(row.order_occurred_at_utc),
        createdAtUtc: iso(row.order_created_at_utc),
        updatedAtUtc: iso(row.order_updated_at_utc),
      },
    subscription: row.subscription_id == null
      ? null
      : {
        subscriptionId: String(row.subscription_id),
        status: String(row.subscription_status),
        startsAtUtc: iso(row.subscription_starts_at_utc),
        currentPeriodEndUtc: nullableIso(row.subscription_period_end_utc),
        cancelledAtUtc: nullableIso(row.subscription_cancelled_at_utc),
        plan: row.plan_id == null
          ? null
          : {
            planId: String(row.plan_id),
            code: String(row.plan_code),
            name: String(row.plan_name),
          },
      },
  };
}

async function getTransaction(sql: AdminSql, transactionId: string) {
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
      t.created_at_utc,
      t.updated_at_utc,
      o.status as order_status,
      o.amount_minor as order_amount_minor,
      o.currency as order_currency,
      o.occurred_at_utc as order_occurred_at_utc,
      o.created_at_utc as order_created_at_utc,
      o.updated_at_utc as order_updated_at_utc,
      s.status as subscription_status,
      s.starts_at_utc as subscription_starts_at_utc,
      s.current_period_end_utc as subscription_period_end_utc,
      s.cancelled_at_utc as subscription_cancelled_at_utc,
      pl.id as plan_id,
      pl.code as plan_code,
      pl.display_name as plan_name
    from commerce.transactions t
    join commerce.products p on p.id = t.product_id
    left join commerce.orders o on o.id = t.order_id
    left join commerce.subscriptions s on s.id = t.subscription_id
    left join commerce.plans pl on pl.id = s.plan_id
    where t.id = ${transactionId}::uuid
    limit 1
  `;
  if (rows.length === 0) return null;
  return mapCommerceTransactionDetailRow(record(rows[0]));
}

async function listProviderEvents(sql: AdminSql, transactionId: string) {
  const rows = await sql`
    select
      id,
      provider_status,
      normalized_status,
      observation_state,
      occurred_at_utc,
      received_at_utc,
      recorded_at_utc
    from commerce.transaction_events
    where transaction_id = ${transactionId}::uuid
    order by received_at_utc desc, id desc
    limit 100
  `;

  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    eventId: String(row.id),
    providerStatus: String(row.provider_status),
    normalizedStatus: String(row.normalized_status),
    observationState: String(row.observation_state),
    occurredAtUtc: iso(row.occurred_at_utc),
    receivedAtUtc: iso(row.received_at_utc),
    recordedAtUtc: iso(row.recorded_at_utc),
  }));
}

async function listRefundRequests(sql: AdminSql, transactionId: string) {
  const rows = await sql`
    select
      id,
      status,
      amount_minor,
      currency,
      reason,
      requested_at_utc,
      reviewed_at_utc,
      resolution_reason,
      updated_at_utc
    from commerce.refund_requests
    where transaction_id = ${transactionId}::uuid
    order by requested_at_utc desc, id desc
    limit 50
  `;

  return (rows as unknown as Record<string, unknown>[]).map((row) => ({
    refundRequestId: String(row.id),
    status: String(row.status),
    amountMinor: String(row.amount_minor),
    currency: String(row.currency),
    reason: String(row.reason),
    requestedAtUtc: iso(row.requested_at_utc),
    reviewedAtUtc: nullableIso(row.reviewed_at_utc),
    resolutionReason: nullableString(row.resolution_reason),
    updatedAtUtc: iso(row.updated_at_utc),
  }));
}

async function listAuditEvents(sql: AdminSql, transactionId: string) {
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
    where resource_type = 'commerce_transaction'
      and resource_id = ${transactionId}
      and action like 'commerce.transaction.%'
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

export function createCommerceTransactionDetailStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async getDetail(transactionId: string, includeAudit: boolean) {
      const transaction = await getTransaction(sql, transactionId);
      if (!transaction) return null;

      const [providerEvents, refundRequests, auditEvents] = await Promise.all([
        listProviderEvents(sql, transactionId),
        listRefundRequests(sql, transactionId),
        includeAudit ? listAuditEvents(sql, transactionId) : Promise.resolve(null),
      ]);

      return {
        transaction,
        providerEvents,
        refundRequests,
        auditEvidence: includeAudit
          ? { state: "ready" as const, items: auditEvents ?? [] }
          : { state: "forbidden" as const },
      };
    },

    async requestRefund(input: {
      actorAccountId: string;
      transactionId: string;
      reason: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.request_commerce_transaction_refund(
          ${input.actorAccountId}::uuid,
          ${input.transactionId}::uuid,
          ${input.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return assertCommerceRefundRequestResult(rows[0]?.result);
    },
  };
}
