import { getAdminSql } from "./database_client.ts";
import type { ProductVersionAdoptionQuery } from "./product_version_analytics.ts";
import type { ProductUpdatePolicyMutation } from "./product_update_policy_mutation.ts";

type Row = Record<string, unknown>;

export function createProductVersionAnalyticsStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  async function listAdoption(query: ProductVersionAdoptionQuery) {
    const rows = await sql`
      select product, platform, app_version, build_number, account_count,
             first_seen_at_utc, last_seen_at_utc, freshness_at_utc
      from analytics.product_version_adoption_v1
      where (${query.product}::text is null or product=${query.product})
        and (${query.platform}::text is null or platform=${query.platform})
      order by product, platform, account_count desc, app_version desc, build_number desc
      limit 500
    `;
    return rows.map(mapAdoption);
  }

  async function listAccountVersions(accountId: string) {
    const rows = await sql`
      select account_id::text, product, platform, app_version, build_number,
             rollout_cohort, first_seen_at_utc, last_seen_at_utc
      from analytics.account_product_version_v1
      where account_id=${accountId}::uuid
      order by product, platform
    `;
    return rows.map(mapAccountVersion);
  }

  async function listPolicies() {
    const rows = await sql`
      select product, platform, minimum_supported_version, recommended_version,
             mode, reason_code, message_key, status, version,
             effective_at_utc, updated_at_utc
      from platform.product_update_policies
      order by product, platform
    `;
    return rows.map(mapPolicy);
  }

  async function listPolicyHistory(
    product: string | null,
    platform: string | null,
  ) {
    const rows = await sql`
      select product, platform, version, snapshot_json, archived_at_utc
      from platform.product_update_policy_history
      where (${product}::text is null or product=${product})
        and (${platform}::text is null or platform=${platform})
      order by archived_at_utc desc, product, platform, version desc
      limit 250
    `;
    return rows.map(mapPolicyHistory);
  }

  async function upsertPolicy(input: {
    actorAccountId: string;
    correlationId: string;
    idempotencyKey: string;
    requestHash: string;
    policy: ProductUpdatePolicyMutation;
  }) {
    const policy = input.policy;
    const rows = await sql`
      select platform.upsert_product_update_policy_admin(
        ${input.actorAccountId}::uuid,
        ${policy.product}::varchar,
        ${policy.platform}::varchar,
        ${policy.minimumSupportedVersion}::varchar,
        ${policy.recommendedVersion}::varchar,
        ${policy.mode}::varchar,
        ${policy.reasonCode}::varchar,
        ${policy.messageKey}::varchar,
        ${policy.status}::varchar,
        ${policy.effectiveAtUtc}::timestamptz,
        ${policy.expectedVersion}::bigint,
        ${policy.reason}::varchar,
        ${input.correlationId}::uuid,
        ${input.idempotencyKey}::varchar,
        ${input.requestHash}::varchar
      ) as result
    `;
    const result = rows[0]?.result;
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      throw new Error("product_update_policy_mutation_invalid");
    }
    return result as Record<string, unknown>;
  }

  return {
    listAdoption,
    listAccountVersions,
    listPolicies,
    listPolicyHistory,
    upsertPolicy,
  };
}

export function mapAdoption(row: Row) {
  return {
    product: String(row.product),
    platform: String(row.platform),
    appVersion: String(row.app_version),
    buildNumber: String(row.build_number),
    accountCount: Number(row.account_count),
    firstSeenAtUtc: iso(row.first_seen_at_utc),
    lastSeenAtUtc: iso(row.last_seen_at_utc),
    freshnessAtUtc: iso(row.freshness_at_utc),
    source: "analytics.product_version_adoption_v1",
  };
}

export function mapAccountVersion(row: Row) {
  return {
    accountId: String(row.account_id),
    product: String(row.product),
    platform: String(row.platform),
    appVersion: String(row.app_version),
    buildNumber: String(row.build_number),
    rolloutCohort: nullableText(row.rollout_cohort),
    firstSeenAtUtc: iso(row.first_seen_at_utc),
    lastSeenAtUtc: iso(row.last_seen_at_utc),
    source: "analytics.account_product_version_v1",
  };
}

function mapPolicy(row: Row) {
  return {
    product: String(row.product),
    platform: String(row.platform),
    minimumSupportedVersion: String(row.minimum_supported_version),
    recommendedVersion: nullableText(row.recommended_version),
    mode: String(row.mode),
    reasonCode: String(row.reason_code),
    messageKey: nullableText(row.message_key),
    status: String(row.status),
    policyVersion: Number(row.version),
    effectiveAtUtc: iso(row.effective_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function mapPolicyHistory(row: Row) {
  const snapshot = row.snapshot_json && typeof row.snapshot_json === "object" &&
      !Array.isArray(row.snapshot_json)
    ? row.snapshot_json as Row
    : {};
  return {
    product: String(row.product),
    platform: String(row.platform),
    policyVersion: Number(row.version),
    minimumSupportedVersion: nullableText(snapshot.minimum_supported_version),
    recommendedVersion: nullableText(snapshot.recommended_version),
    mode: nullableText(snapshot.mode),
    reasonCode: nullableText(snapshot.reason_code),
    messageKey: nullableText(snapshot.message_key),
    status: nullableText(snapshot.status),
    effectiveAtUtc: nullableIso(snapshot.effective_at_utc),
    updatedAtUtc: nullableIso(snapshot.updated_at_utc),
    archivedAtUtc: iso(row.archived_at_utc),
  };
}

function nullableText(value: unknown): string | null {
  return value == null ? null : String(value);
}

function nullableIso(value: unknown): string | null {
  if (value == null) return null;
  const date = new Date(String(value));
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function iso(value: unknown): string {
  return new Date(String(value)).toISOString();
}
