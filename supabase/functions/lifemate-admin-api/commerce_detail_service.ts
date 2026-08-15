import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { CommerceDetailQuery } from "./commerce_detail.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function nullableIso(value: unknown): string | null {
  return value == null ? null : iso(value);
}

function row(value: unknown): Record<string, unknown> {
  return value as Record<string, unknown>;
}

async function getPlanRecord(sql: AdminSql, planId: string) {
  const rows = await sql`
    select pl.id as plan_id,
           pl.code as plan_code,
           pl.display_name as plan_name,
           pl.status as plan_status,
           pl.created_at_utc,
           p.id as product_id,
           p.code as product_code,
           p.display_name as product_name,
           p.status as product_status
    from commerce.plans pl
    join commerce.products p on p.id = pl.product_id
    where pl.id = ${planId}::uuid
    limit 1
  `;
  if (rows.length === 0) return null;
  const value = row(rows[0]);
  return {
    plan: {
      id: String(value.plan_id),
      code: String(value.plan_code),
      name: String(value.plan_name),
      status: String(value.plan_status),
      createdAtUtc: iso(value.created_at_utc),
    },
    product: {
      id: String(value.product_id),
      code: String(value.product_code),
      name: String(value.product_name),
      status: String(value.product_status),
    },
  };
}

async function listPlanFeatureRules(sql: AdminSql, productId: string) {
  const countRows = await sql`
    select count(*)::integer as total
    from commerce.product_features
    where product_id = ${productId}::uuid
  `;
  const rows = await sql`
    select f.id as feature_id,
           f.code as feature_code,
           f.description,
           pf.minimum_plan_code
    from commerce.product_features pf
    join commerce.features f on f.id = pf.feature_id
    where pf.product_id = ${productId}::uuid
    order by f.code asc
    limit 250
  `;
  return {
    total: Number(countRows[0]?.total ?? 0),
    items: (rows as unknown as Record<string, unknown>[]).map((value) => ({
      featureId: String(value.feature_id),
      featureCode: String(value.feature_code),
      description: String(value.description),
      minimumPlanCode: value.minimum_plan_code == null
        ? null
        : String(value.minimum_plan_code),
    })),
  };
}

async function listPlanPrices(sql: AdminSql, planId: string) {
  const countRows = await sql`
    select count(*)::integer as total
    from commerce.prices
    where plan_id = ${planId}::uuid
  `;
  const rows = await sql`
    select id,
           country_code,
           currency,
           store_provider,
           billing_period_months,
           amount_minor,
           status,
           effective_from_utc,
           effective_to_utc
    from commerce.prices
    where plan_id = ${planId}::uuid
    order by effective_from_utc desc, id desc
    limit 100
  `;
  return {
    total: Number(countRows[0]?.total ?? 0),
    items: (rows as unknown as Record<string, unknown>[]).map((value) => ({
      priceId: String(value.id),
      countryCode: value.country_code == null
        ? null
        : String(value.country_code),
      currency: String(value.currency),
      storeProvider: String(value.store_provider),
      billingPeriodMonths: Number(value.billing_period_months),
      amountMinor: String(value.amount_minor),
      status: String(value.status),
      effectiveFromUtc: iso(value.effective_from_utc),
      effectiveToUtc: nullableIso(value.effective_to_utc),
    })),
  };
}

async function getPlanSubscriptionSummary(sql: AdminSql, planId: string) {
  const rows = await sql`
    select count(*)::integer as total,
           count(*) filter (where status = 'Trial')::integer as trial,
           count(*) filter (where status = 'Active')::integer as active,
           count(*) filter (where status = 'PastDue')::integer as past_due,
           count(*) filter (where status = 'Cancelled')::integer as cancelled,
           count(*) filter (where status = 'Expired')::integer as expired,
           count(*) filter (where status = 'Refunded')::integer as refunded
    from commerce.subscriptions
    where plan_id = ${planId}::uuid
  `;
  const value = row(rows[0] ?? {});
  return {
    total: Number(value.total ?? 0),
    trial: Number(value.trial ?? 0),
    active: Number(value.active ?? 0),
    pastDue: Number(value.past_due ?? 0),
    cancelled: Number(value.cancelled ?? 0),
    expired: Number(value.expired ?? 0),
    refunded: Number(value.refunded ?? 0),
  };
}

async function listPlanSubscriptions(
  sql: AdminSql,
  planId: string,
  query: CommerceDetailQuery,
) {
  const rows = await sql`
    select id,
           status,
           starts_at_utc,
           current_period_end_utc,
           cancelled_at_utc,
           created_at_utc,
           updated_at_utc
    from commerce.subscriptions
    where plan_id = ${planId}::uuid
    order by updated_at_utc desc, id desc
    limit ${query.pageSize} offset ${query.offset}
  `;
  return (rows as unknown as Record<string, unknown>[]).map((value) => ({
    subscriptionId: String(value.id),
    status: String(value.status),
    startsAtUtc: iso(value.starts_at_utc),
    currentPeriodEndUtc: nullableIso(value.current_period_end_utc),
    cancelledAtUtc: nullableIso(value.cancelled_at_utc),
    createdAtUtc: iso(value.created_at_utc),
    updatedAtUtc: iso(value.updated_at_utc),
  }));
}

async function getFeatureRecord(sql: AdminSql, featureCode: string) {
  const rows = await sql`
    select id, code, description, created_at_utc
    from commerce.features
    where code = ${featureCode}
    limit 1
  `;
  if (rows.length === 0) return null;
  const value = row(rows[0]);
  return {
    id: String(value.id),
    code: String(value.code),
    description: String(value.description),
    createdAtUtc: iso(value.created_at_utc),
  };
}

async function listFeatureProductRules(sql: AdminSql, featureId: string) {
  const countRows = await sql`
    select count(*)::integer as total
    from commerce.product_features
    where feature_id = ${featureId}::uuid
  `;
  const rows = await sql`
    select p.id as product_id,
           p.code as product_code,
           p.display_name as product_name,
           p.status as product_status,
           pf.minimum_plan_code
    from commerce.product_features pf
    join commerce.products p on p.id = pf.product_id
    where pf.feature_id = ${featureId}::uuid
    order by p.display_name asc, p.code asc
    limit 100
  `;
  return {
    total: Number(countRows[0]?.total ?? 0),
    items: (rows as unknown as Record<string, unknown>[]).map((value) => ({
      productId: String(value.product_id),
      productCode: String(value.product_code),
      productName: String(value.product_name),
      productStatus: String(value.product_status),
      minimumPlanCode: value.minimum_plan_code == null
        ? null
        : String(value.minimum_plan_code),
    })),
  };
}

async function getFeatureEntitlementSummary(sql: AdminSql, featureId: string) {
  const rows = await sql`
    select count(*)::integer as total,
           count(*) filter (
             where status = 'Active'
               and starts_at_utc <= now()
               and (expires_at_utc is null or expires_at_utc > now())
           )::integer as active,
           count(*) filter (
             where status = 'Expired'
                or (
                  status = 'Active'
                  and expires_at_utc is not null
                  and expires_at_utc <= now()
                )
           )::integer as expired,
           count(*) filter (where status = 'Revoked')::integer as revoked,
           count(*) filter (
             where status = 'Active' and starts_at_utc > now()
           )::integer as scheduled
    from commerce.entitlements
    where feature_id = ${featureId}::uuid
  `;
  const value = row(rows[0] ?? {});
  return {
    total: Number(value.total ?? 0),
    active: Number(value.active ?? 0),
    expired: Number(value.expired ?? 0),
    revoked: Number(value.revoked ?? 0),
    scheduled: Number(value.scheduled ?? 0),
  };
}

async function listFeatureEntitlements(
  sql: AdminSql,
  featureId: string,
  query: CommerceDetailQuery,
) {
  const rows = await sql`
    select id,
           status as stored_status,
           case
             when status = 'Active' and starts_at_utc > now() then 'Scheduled'
             when status = 'Active'
               and expires_at_utc is not null
               and expires_at_utc <= now() then 'Expired'
             else status
           end as effective_status,
           source,
           starts_at_utc,
           expires_at_utc,
           created_at_utc,
           updated_at_utc,
           case
             when grantee_account_id is not null and beneficiary_person_id is not null
               then 'AccountAndPerson'
             when grantee_account_id is not null then 'Account'
             else 'Person'
           end as target_kind
    from commerce.entitlements
    where feature_id = ${featureId}::uuid
    order by updated_at_utc desc, id desc
    limit ${query.pageSize} offset ${query.offset}
  `;
  return (rows as unknown as Record<string, unknown>[]).map((value) => ({
    entitlementId: String(value.id),
    source: String(value.source),
    storedStatus: String(value.stored_status),
    effectiveStatus: String(value.effective_status),
    targetKind: String(value.target_kind),
    startsAtUtc: iso(value.starts_at_utc),
    expiresAtUtc: nullableIso(value.expires_at_utc),
    createdAtUtc: iso(value.created_at_utc),
    updatedAtUtc: iso(value.updated_at_utc),
  }));
}

async function listFeatureEntitlementEvents(sql: AdminSql, featureId: string) {
  const countRows = await sql`
    select count(*)::integer as total
    from commerce.entitlement_events ev
    join commerce.entitlements e on e.id = ev.entitlement_id
    where e.feature_id = ${featureId}::uuid
  `;
  const rows = await sql`
    select ev.id,
           ev.entitlement_id,
           ev.event_type,
           ev.occurred_at_utc,
           ev.recorded_at_utc
    from commerce.entitlement_events ev
    join commerce.entitlements e on e.id = ev.entitlement_id
    where e.feature_id = ${featureId}::uuid
    order by ev.occurred_at_utc desc, ev.id desc
    limit 25
  `;
  return {
    total: Number(countRows[0]?.total ?? 0),
    items: (rows as unknown as Record<string, unknown>[]).map((value) => ({
      eventId: String(value.id),
      entitlementId: String(value.entitlement_id),
      eventType: String(value.event_type),
      occurredAtUtc: iso(value.occurred_at_utc),
      recordedAtUtc: iso(value.recorded_at_utc),
    })),
  };
}

export function createCommerceDetailStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async getPlan(planId: string, query: CommerceDetailQuery) {
      const record = await getPlanRecord(sql, planId);
      if (!record) return null;
      const [featureRules, prices, subscriptionSummary, subscriptions] =
        await Promise.all([
          listPlanFeatureRules(sql, record.product.id),
          listPlanPrices(sql, planId),
          getPlanSubscriptionSummary(sql, planId),
          listPlanSubscriptions(sql, planId, query),
        ]);
      return {
        ...record,
        featureRules,
        prices,
        subscriptionSummary,
        subscriptions: {
          items: subscriptions,
          total: subscriptionSummary.total,
        },
        changeHistory: {
          instrumented: false,
          reason:
            "Plan lifecycle changes are not yet stored as a dedicated event stream.",
        },
        transactionLinkage: {
          instrumented: false,
          reason:
            "Orders and transactions are intentionally deferred to the ADM-COM-003 canonical transaction surface.",
        },
      };
    },

    async getEntitlementFeature(
      featureCode: string,
      query: CommerceDetailQuery,
    ) {
      const feature = await getFeatureRecord(sql, featureCode);
      if (!feature) return null;
      const [productRules, summary, entitlements, eventHistory] = await Promise
        .all([
          listFeatureProductRules(sql, feature.id),
          getFeatureEntitlementSummary(sql, feature.id),
          listFeatureEntitlements(sql, feature.id, query),
          listFeatureEntitlementEvents(sql, feature.id),
        ]);
      return {
        feature,
        productRules,
        summary,
        entitlements: { items: entitlements, total: summary.total },
        eventHistory,
      };
    },
  };
}
