import type { AdminSql } from "./database_client.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

export async function getUserCommerceSummary(
  sql: AdminSql,
  accountId: string,
  personId: string | null,
) {
  const subscriptions = await sql`
    select distinct subscription.id,
           product.code as product_code,
           product.display_name as product_name,
           plan.code as plan_code,
           plan.display_name as plan_name,
           subscription.status,
           subscription.starts_at_utc,
           subscription.current_period_end_utc
    from commerce.subscriptions subscription
    join commerce.products product on product.id = subscription.product_id
    join commerce.plans plan on plan.id = subscription.plan_id
    where subscription.payer_account_id = ${accountId}::uuid
       or subscription.owner_account_id = ${accountId}::uuid
       or (${personId}::uuid is not null and subscription.beneficiary_person_id = ${personId}::uuid)
    order by subscription.starts_at_utc desc, subscription.id desc
    limit 50
  `;

  const entitlements = await sql`
    select distinct entitlement.id,
           feature.code as feature_code,
           entitlement.source,
           entitlement.status,
           entitlement.starts_at_utc,
           entitlement.expires_at_utc,
           entitlement.version
    from commerce.entitlements entitlement
    join commerce.features feature on feature.id = entitlement.feature_id
    where entitlement.grantee_account_id = ${accountId}::uuid
       or (${personId}::uuid is not null and entitlement.beneficiary_person_id = ${personId}::uuid)
    order by entitlement.starts_at_utc desc, entitlement.id desc
    limit 100
  `;

  return {
    subscriptions: subscriptions.map((row) => ({
      id: String(row.id),
      productCode: String(row.product_code),
      productName: String(row.product_name),
      planCode: String(row.plan_code),
      planName: String(row.plan_name),
      status: String(row.status),
      startsAtUtc: iso(row.starts_at_utc),
      currentPeriodEndUtc: row.current_period_end_utc == null
        ? null
        : iso(row.current_period_end_utc),
    })),
    entitlements: entitlements.map((row) => ({
      id: String(row.id),
      featureCode: String(row.feature_code),
      source: String(row.source),
      status: String(row.status),
      startsAtUtc: iso(row.starts_at_utc),
      expiresAtUtc: row.expires_at_utc == null
        ? null
        : iso(row.expires_at_utc),
      version: Number(row.version),
    })),
  };
}
