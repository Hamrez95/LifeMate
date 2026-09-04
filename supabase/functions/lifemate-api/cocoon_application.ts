import { getLifeMateSql } from "./database_client.ts";

export type CocoonApplicationAvailability = "available" | "unavailable";
export type CocoonApplicationEnrollmentState =
  | "active"
  | "suspended"
  | "left"
  | "not_enrolled";
export type CocoonCommerceEligibilityState =
  | "entitled"
  | "conversion_eligible"
  | "offer_available"
  | "not_entitled"
  | "unavailable"
  | "error";

export interface CocoonApplicationSnapshot {
  availability: CocoonApplicationAvailability;
  enrollmentState: CocoonApplicationEnrollmentState;
}

export interface CocoonCommerceEligibilitySnapshot {
  state: CocoonCommerceEligibilityState;
  offerAvailable: boolean;
  conversionEligible: boolean;
}

export function classifyCocoonCommerceEligibility(input: {
  productAvailable: boolean;
  entitled: boolean;
  offerAvailable: boolean;
  conversionEligible: boolean;
  dependencyError?: boolean;
}): CocoonCommerceEligibilitySnapshot {
  if (input.dependencyError) {
    return { state: "error", offerAvailable: false, conversionEligible: false };
  }
  if (!input.productAvailable) {
    return {
      state: "unavailable",
      offerAvailable: false,
      conversionEligible: false,
    };
  }
  if (input.entitled) {
    return {
      state: "entitled",
      offerAvailable: input.offerAvailable,
      conversionEligible: false,
    };
  }
  if (input.conversionEligible) {
    return {
      state: "conversion_eligible",
      offerAvailable: input.offerAvailable,
      conversionEligible: true,
    };
  }
  if (input.offerAvailable) {
    return {
      state: "offer_available",
      offerAvailable: true,
      conversionEligible: false,
    };
  }
  return {
    state: "not_entitled",
    offerAvailable: false,
    conversionEligible: false,
  };
}

export function createCocoonApplicationBoundary(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function resolveAndEnroll(
    accountId: string,
  ): Promise<CocoonApplicationSnapshot> {
    const applications = await sql`
      select id,status
      from ecosystem.applications
      where code='cocoonmate'
      limit 1
    `;
    const application = applications[0];
    if (!application || String(application.status) !== "Active") {
      return { availability: "unavailable", enrollmentState: "not_enrolled" };
    }

    // Cocoon enrollment is created only after an authenticated Cocoon bootstrap.
    // It deliberately does not create pregnancy state, consent, grants or Commerce.
    await sql`
      insert into ecosystem.app_enrollments(
        account_id,application_id,status,enrolled_at_utc,last_active_at_utc
      )
      values(
        ${accountId}::uuid,
        ${String(application.id)}::uuid,
        'Active',now(),now()
      )
      on conflict(account_id,application_id) do nothing
    `;
    await sql`
      update ecosystem.app_enrollments
      set last_active_at_utc=now()
      where account_id=${accountId}::uuid
        and application_id=${String(application.id)}::uuid
        and status='Active'
    `;

    const enrollmentRows = await sql`
      select status
      from ecosystem.app_enrollments
      where account_id=${accountId}::uuid
        and application_id=${String(application.id)}::uuid
      limit 1
    `;
    const status = String(enrollmentRows[0]?.status ?? "");
    const enrollmentState: CocoonApplicationEnrollmentState =
      status === "Active"
        ? "active"
        : status === "Suspended"
        ? "suspended"
        : status === "Left"
        ? "left"
        : "not_enrolled";
    return { availability: "available", enrollmentState };
  }

  async function commerceEligibility(
    accountId: string,
  ): Promise<CocoonCommerceEligibilitySnapshot> {
    try {
      const rows = await sql`
        with cocoon_product as (
          select id,lifecycle_status
          from commerce.products
          where code='cocoonmate' and status='Active'
          limit 1
        ), period_product as (
          select id
          from commerce.products
          where code='period-calendar' and status='Active'
          limit 1
        )
        select
          exists(select 1 from cocoon_product where lifecycle_status<>'Retired') as product_available,
          exists(
            select 1
            from commerce.subscriptions s
            join cocoon_product cp on cp.id=s.product_id
            where s.owner_account_id=${accountId}::uuid
              and s.status in ('Active','Trial')
              and s.starts_at_utc<=now()
              and (s.current_period_end_utc is null or s.current_period_end_utc>now())
          ) as entitled,
          exists(
            select 1
            from commerce.offers o
            join cocoon_product cp on cp.id=o.product_id
            where o.status='Published'
              and cp.lifecycle_status='Published'
          ) as offer_available,
          exists(
            select 1
            from commerce.subscriptions source
            join period_product pp on pp.id=source.product_id
            join commerce.subscription_payment_sources ps on ps.subscription_id=source.id
            join commerce.transaction_effective_state_v1 tx on tx.transaction_id=ps.transaction_id
            where source.owner_account_id=${accountId}::uuid
              and source.status='Active'
              and source.starts_at_utc<=now()
              and source.current_period_end_utc>now()
              and ps.service_period_end_utc>now()
              and tx.effective_normalized_status in ('Succeeded','Refunded')
              and tx.net_collected_minor>0
              and not exists(
                select 1 from commerce.subscription_conversions c
                where c.source_subscription_id=source.id
              )
              and not exists(
                select 1
                from commerce.subscriptions existing
                join cocoon_product cp2 on cp2.id=existing.product_id
                where existing.owner_account_id=${accountId}::uuid
                  and existing.status='Active'
                  and (existing.current_period_end_utc is null or existing.current_period_end_utc>now())
              )
          ) as conversion_eligible
      `;
      const row = rows[0] ?? {};
      return classifyCocoonCommerceEligibility({
        productAvailable: row.product_available === true,
        entitled: row.entitled === true,
        offerAvailable: row.offer_available === true,
        conversionEligible: row.conversion_eligible === true,
      });
    } catch {
      return classifyCocoonCommerceEligibility({
        productAvailable: false,
        entitled: false,
        offerAvailable: false,
        conversionEligible: false,
        dependencyError: true,
      });
    }
  }

  return { resolveAndEnroll, commerceEligibility };
}
