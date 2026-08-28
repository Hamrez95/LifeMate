import { getLifeMateSql } from "./database_client.ts";

type Row = Record<string, unknown>;

export type PrivacyDirectoryQuery = {
  q: string | null;
  status: string | null;
  page: number;
  pageSize: number;
};

export type PrivacyMutationContext = {
  actorAccountId: string;
  correlationId: string;
  idempotencyKey: string;
  requestHash: string;
};

export function createPrivacyConsentStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  return {
    async listDocuments(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows = await sql`
        select *, count(*) over() as total_count
        from consent.admin_document_directory_v1 d
        where (${query.status}::text is null or d.status=${query.status})
          and (
            ${query.q}::text is null
            or d.purpose ilike '%' || ${query.q} || '%'
            or d.title ilike '%' || ${query.q} || '%'
            or d.version ilike '%' || ${query.q} || '%'
          )
        order by d.updated_at_utc desc,d.document_id desc
        limit ${query.pageSize} offset ${offset}
      `;
      return page(rows as unknown as Row[], query);
    },

    async listAcceptances(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows = await sql`
        select *, count(*) over() as total_count
        from consent.admin_legal_acceptance_directory_v1 a
        where (
          ${query.q}::text is null
          or a.account_id::text=${query.q}
          or a.purpose ilike '%' || ${query.q} || '%'
          or a.document_title ilike '%' || ${query.q} || '%'
          or a.version ilike '%' || ${query.q} || '%'
        )
        order by a.accepted_at_utc desc,a.account_id desc,a.document_id desc
        limit ${query.pageSize} offset ${offset}
      `;
      return page(rows as unknown as Row[], query);
    },

    async listConsents(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows = await sql`
        select *, count(*) over() as total_count
        from consent.admin_user_consent_directory_v1 c
        where (${query.status}::text is null or c.status=${query.status})
          and (
            ${query.q}::text is null
            or c.subject_person_id::text=${query.q}
            or c.actor_account_id::text=${query.q}
            or c.purpose ilike '%' || ${query.q} || '%'
            or c.scope_key ilike '%' || ${query.q} || '%'
          )
        order by c.updated_at_utc desc,c.consent_record_id desc
        limit ${query.pageSize} offset ${offset}
      `;
      return page(rows as unknown as Row[], query);
    },

    async listPreferences(query: PrivacyDirectoryQuery) {
      const offset = (query.page - 1) * query.pageSize;
      const rows = await sql`
        select *, count(*) over() as total_count
        from consent.admin_preference_directory_v1 p
        where (${query.status}::text is null or (case when p.enabled then 'Enabled' else 'Disabled' end)=${query.status})
          and (
            ${query.q}::text is null
            or p.account_id::text=${query.q}
            or p.subject_person_id::text=${query.q}
            or p.purpose ilike '%' || ${query.q} || '%'
          )
        order by p.updated_at_utc desc nulls last,p.account_id desc,p.purpose
        limit ${query.pageSize} offset ${offset}
      `;
      return page(rows as unknown as Row[], query);
    },

    async getCoverage(actorAccountId: string, jurisdiction: string) {
      const rows = await sql`
        select consent.admin_acceptance_coverage(
          ${actorAccountId}::uuid,${jurisdiction}::varchar
        ) as result
      `;
      return resultObject(rows[0]?.result, "privacy_coverage_result_invalid");
    },

    async listPurposeCatalog(actorAccountId: string) {
      const rows = await sql`
        select consent.admin_preference_purpose_catalog(${actorAccountId}::uuid) as result
      `;
      return resultObject(rows[0]?.result, "privacy_purpose_catalog_result_invalid");
    },

    async getAccountSummary(actorAccountId: string, accountId: string, jurisdiction: string) {
      const rows = await sql`
        select consent.admin_account_privacy_summary(
          ${actorAccountId}::uuid,${accountId}::uuid,${jurisdiction}::varchar
        ) as result
      `;
      return resultObject(rows[0]?.result, "privacy_account_summary_result_invalid");
    },

    async createDocument(input: PrivacyMutationContext & {
      purpose: string;
      version: string;
      jurisdiction: string;
      title: string;
      documentHash: string;
      contentUri: string;
      effectiveAtUtc: string | null;
      reasonCode: string;
    }) {
      const rows = await sql`
        select consent.admin_create_document_idempotent(
          ${input.actorAccountId}::uuid,${input.purpose}::varchar,${input.version}::varchar,
          ${input.jurisdiction}::varchar,${input.title}::varchar,${input.documentHash}::varchar,
          ${input.contentUri}::text,${input.effectiveAtUtc}::timestamptz,${input.reasonCode}::varchar,
          ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return resultObject(rows[0]?.result, "privacy_document_create_result_invalid");
    },

    async publishDocument(input: PrivacyMutationContext & {
      documentId: string;
      expectedUpdatedAt: string;
      effectiveAtUtc: string;
      reasonCode: string;
    }) {
      const rows = await sql`
        select consent.admin_publish_document_idempotent(
          ${input.actorAccountId}::uuid,${input.documentId}::uuid,
          ${input.expectedUpdatedAt}::timestamptz,${input.effectiveAtUtc}::timestamptz,
          ${input.reasonCode}::varchar,${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return resultObject(rows[0]?.result, "privacy_document_publish_result_invalid");
    },

    async retireDocument(input: PrivacyMutationContext & {
      documentId: string;
      expectedUpdatedAt: string;
      reasonCode: string;
    }) {
      const rows = await sql`
        select consent.admin_retire_document_idempotent(
          ${input.actorAccountId}::uuid,${input.documentId}::uuid,
          ${input.expectedUpdatedAt}::timestamptz,${input.reasonCode}::varchar,
          ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return resultObject(rows[0]?.result, "privacy_retire_result_invalid");
    },

    async updatePurpose(input: PrivacyMutationContext & {
      purpose: string;
      expectedUpdatedAt: string;
      description: string;
      policyVersion: string;
      status: string;
      reasonCode: string;
    }) {
      const rows = await sql`
        select consent.admin_update_preference_purpose_idempotent(
          ${input.actorAccountId}::uuid,${input.purpose}::varchar,
          ${input.expectedUpdatedAt}::timestamptz,${input.description}::varchar,
          ${input.policyVersion}::varchar,${input.status}::varchar,${input.reasonCode}::varchar,
          ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return resultObject(rows[0]?.result, "privacy_purpose_update_result_invalid");
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

function resultObject(value: unknown, code: string): Row {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(code);
  }
  return value as Row;
}

function mapRow(row: Row): Row {
  const result: Row = {};
  for (const [key, value] of Object.entries(row)) {
    result[toCamel(key)] = value instanceof Date ? value.toISOString() : value;
  }
  return result;
}

function toCamel(value: string): string {
  return value.replace(/_([a-z])/g, (_, letter: string) => letter.toUpperCase());
}
