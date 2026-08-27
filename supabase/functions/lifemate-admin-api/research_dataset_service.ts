import { getAdminSql } from "./database_client.ts";

export function createResearchDatasetStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async list(actorAccountId: string) {
      const rows = await sql`
        select * from analytics.list_research_datasets(${actorAccountId}::uuid)
      `;
      return rows.map((row) => ({
        datasetId: String(row.dataset_id),
        name: String(row.name),
        purpose: String(row.purpose),
        sourceCategory: String(row.source_category),
        filters: row.filter_json,
        datasetVersion: Number(row.dataset_version),
        status: String(row.status),
        privacyPolicyVersion: Number(row.privacy_policy_version),
        ageBucketYears: row.age_bucket_years == null ? null : Number(row.age_bucket_years),
        minimumCohortSize: Number(row.minimum_cohort_size),
        smallCellThreshold: Number(row.small_cell_threshold),
        quasiIdentifierRules: row.quasi_identifier_rules,
        rowMode: String(row.row_mode),
        updatedAtUtc: new Date(String(row.updated_at_utc)).toISOString(),
      }));
    },

    async create(input: {
      actorAccountId: string;
      name: string;
      purpose: string;
      sourceCategory: string;
      filters: Record<string, unknown>;
      ageBucketYears: number | null;
      minimumCohortSize: number;
      smallCellThreshold: number;
      quasiIdentifierRules: Record<string, unknown>;
      rowMode: "Aggregate" | "Pseudonymous";
    }) {
      const rows = await sql`
        select analytics.create_research_dataset(
          ${input.actorAccountId}::uuid,
          ${input.name}::varchar,
          ${input.purpose}::varchar,
          ${input.sourceCategory}::varchar,
          ${sql.json(input.filters)},
          ${input.ageBucketYears}::smallint,
          ${input.minimumCohortSize}::integer,
          ${input.smallCellThreshold}::integer,
          ${sql.json(input.quasiIdentifierRules)},
          ${input.rowMode}::varchar
        ) as dataset_id
      `;
      return { datasetId: String(rows[0]?.dataset_id) };
    },
  };
}
