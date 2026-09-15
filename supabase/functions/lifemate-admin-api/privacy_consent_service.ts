import { getLifeMateSql } from "./database_client.ts";

type Row = Record<string, unknown>;

export type PrivacyDirectoryQuery = {
  q: string | null;
  status: string | null;
  page: number;
  pageSize: number;
};

function result(rows: Row[], code: string): Row {
  const value = rows[0]?.result;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(code);
  }
  return value as Row;
}

export function createPrivacyConsentStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  return {
    async listDocuments(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows =
        await sql`select *,count(*) over() as total_count from consent.admin_document_directory_v1 d where (${query.status}::text is null or d.status=${query.status}) and (${query.q}::text is null or d.purpose ilike '%'||${query.q}||'%' or d.title ilike '%'||${query.q}||'%' or d.version ilike '%'||${query.q}||'%') order by d.updated_at_utc desc,d.document_id desc limit ${query.pageSize} offset ${offset}`;
      return page(rows as unknown as Row[], query);
    },
    async listAcceptances(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows =
        await sql`select *,count(*) over() as total_count from consent.admin_legal_acceptance_directory_v1 a where (${query.q}::text is null or a.account_id::text=${query.q} or a.purpose ilike '%'||${query.q}||'%' or a.document_title ilike '%'||${query.q}||'%' or a.version ilike '%'||${query.q}||'%') order by a.accepted_at_utc desc,a.account_id desc,a.document_id desc limit ${query.pageSize} offset ${offset}`;
      return page(rows as unknown as Row[], query);
    },
    async listConsents(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows =
        await sql`select *,count(*) over() as total_count from consent.admin_user_consent_directory_v1 c where (${query.status}::text is null or c.status=${query.status}) and (${query.q}::text is null or c.subject_person_id::text=${query.q} or c.actor_account_id::text=${query.q} or c.purpose ilike '%'||${query.q}||'%' or c.scope_key ilike '%'||${query.q}||'%') order by c.updated_at_utc desc,c.consent_record_id desc limit ${query.pageSize} offset ${offset}`;
      return page(rows as unknown as Row[], query);
    },
    async listPreferences(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows =
        await sql`select *,count(*) over() as total_count from consent.admin_preference_directory_v1 p where (${query.status}::text is null or (case when p.enabled then 'Enabled' else 'Disabled' end)=${query.status}) and (${query.q}::text is null or p.account_id::text=${query.q} or p.subject_person_id::text=${query.q} or p.purpose ilike '%'||${query.q}||'%') order by p.updated_at_utc desc nulls last,p.account_id desc,p.purpose limit ${query.pageSize} offset ${offset}`;
      return page(rows as unknown as Row[], query);
    },
    async listPreferencePurposePolicies(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows =
        await sql`select *,count(*) over() as total_count from consent.admin_preference_purpose_policy_directory_v1 p where (${query.status}::text is null or p.status=${query.status}) and (${query.q}::text is null or p.purpose ilike '%'||${query.q}||'%' or p.description ilike '%'||${query.q}||'%' or p.policy_version ilike '%'||${query.q}||'%') order by p.updated_at_utc desc,p.purpose limit ${query.pageSize} offset ${offset}`;
      return page(rows as unknown as Row[], query);
    },
    async coverage(actorAccountId: string, jurisdiction: string) {
      return result(
        await sql`select consent.admin_legal_acceptance_coverage(${actorAccountId}::uuid,${jurisdiction}::varchar) as result` as unknown as Row[],
        "privacy_coverage_result_invalid",
      );
    },
    async userSummary(actorAccountId: string, targetAccountId: string) {
      return result(
        await sql`select consent.admin_user_privacy_summary(${actorAccountId}::uuid,${targetAccountId}::uuid) as result` as unknown as Row[],
        "privacy_summary_result_invalid",
      );
    },
    async createDocument(input: Record<string, string>) {
      return result(
        await sql`select consent.admin_create_document_draft_idempotent(${input.actorAccountId}::uuid,${input.purpose}::varchar,${input.version}::varchar,${input.jurisdiction}::varchar,${input.title}::varchar,${input.documentHash}::varchar,${input.contentUri}::text,${input.effectiveAtUtc}::timestamptz,${input.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result` as unknown as Row[],
        "privacy_create_result_invalid",
      );
    },
    async publishDocument(input: Record<string, string>) {
      return result(
        await sql`select consent.admin_publish_document_idempotent(${input.actorAccountId}::uuid,${input.documentId}::uuid,${input.expectedUpdatedAt}::timestamptz,${input.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result` as unknown as Row[],
        "privacy_publish_result_invalid",
      );
    },
    async retireDocument(input: Record<string, string>) {
      return result(
        await sql`select consent.admin_retire_document_idempotent(${input.actorAccountId}::uuid,${input.documentId}::uuid,${input.expectedUpdatedAt}::timestamptz,${input.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result` as unknown as Row[],
        "privacy_retire_result_invalid",
      );
    },
    async updatePreference(input: Record<string, string>) {
      return result(
        await sql`select consent.admin_update_preference_purpose_idempotent(${input.actorAccountId}::uuid,${input.purpose}::varchar,${input.expectedUpdatedAt}::timestamptz,${input.description}::varchar,${input.policyVersion}::varchar,${input.status}::varchar,${input.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar) as result` as unknown as Row[],
        "privacy_preference_result_invalid",
      );
    },
  };
}

function page(rows: Row[], query: PrivacyDirectoryQuery) {
  const total = rows.length === 0 ? 0 : Number(rows[0].total_count ?? 0);
  return {
    items: rows.map(({ total_count: _total, ...row }) => mapRow(row)),
    page: query.page,
    pageSize: query.pageSize,
    total,
  };
}
function mapRow(row: Row): Row {
  const mapped: Row = {};
  for (const [key, value] of Object.entries(row)) {
    mapped[
      key.replace(/_([a-z])/g, (_, letter: string) => letter.toUpperCase())
    ] = value instanceof Date ? value.toISOString() : value;
  }
  return mapped;
}
