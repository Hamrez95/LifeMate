import { type AdminSql, getAdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export type ResearchDatasetKind =
  | "HealthObservationAggregate"
  | "DoseAdherenceAggregate"
  | "TreatmentAggregate"
  | "WomenCycleAggregate";

async function consumeIdempotency<T>(input: {
  sql: AdminSql;
  actorAccountId: string;
  operation: string;
  idempotencyKey: string;
  requestHash: string;
  work: (tx: AdminSql) => Promise<T>;
}): Promise<T> {
  return await input.sql.begin(async (tx) => {
    const inserted = await tx`
      insert into admin.idempotency_keys(
        actor_account_id,operation,idempotency_key,request_hash,status,expires_at_utc
      ) values (
        ${input.actorAccountId}::uuid,${input.operation},${input.idempotencyKey},${input.requestHash},'Processing',now()+interval '24 hours'
      )
      on conflict (actor_account_id,operation,idempotency_key) do nothing
      returning idempotency_key
    `;
    if (inserted.length === 0) {
      const existing = await tx`
        select request_hash,status,response_json
        from admin.idempotency_keys
        where actor_account_id=${input.actorAccountId}::uuid
          and operation=${input.operation}
          and idempotency_key=${input.idempotencyKey}
        for update
      `;
      if (existing.length === 0) {
        throw new ApiError(
          409,
          "idempotency_conflict",
          "Idempotency state changed; retry safely.",
        );
      }
      if (String(existing[0].request_hash) !== input.requestHash) {
        throw new ApiError(
          409,
          "idempotency_key_reused",
          "Idempotency key was already used with a different request.",
        );
      }
      if (String(existing[0].status) === "Completed") {
        return existing[0].response_json as T;
      }
      throw new ApiError(
        409,
        "request_in_progress",
        "An equivalent research operation is already in progress.",
      );
    }
    const response = await input.work(tx as AdminSql);
    await tx`
      update admin.idempotency_keys
      set status='Completed',response_status=201,response_json=${
      tx.json(response as object)
    },updated_at_utc=now()
      where actor_account_id=${input.actorAccountId}::uuid
        and operation=${input.operation}
        and idempotency_key=${input.idempotencyKey}
    `;
    return response;
  }) as T;
}

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
        datasetKind: String(row.dataset_kind) as ResearchDatasetKind,
        purpose: String(row.purpose),
        sourceCategory: String(row.source_category),
        filters: row.filter_json,
        datasetVersion: Number(row.dataset_version),
        status: String(row.status),
        privacyPolicyVersion: Number(row.privacy_policy_version),
        ageBucketYears: row.age_bucket_years == null
          ? null
          : Number(row.age_bucket_years),
        minimumCohortSize: Number(row.minimum_cohort_size),
        smallCellThreshold: Number(row.small_cell_threshold),
        quasiIdentifierRules: row.quasi_identifier_rules,
        rowMode: String(row.row_mode),
        updatedAtUtc: new Date(String(row.updated_at_utc)).toISOString(),
      }));
    },

    async preview(
      actorAccountId: string,
      datasetId: string,
      jurisdiction = "GLOBAL",
    ) {
      const rows = await sql`
        select analytics.preview_research_dataset(
          ${actorAccountId}::uuid,
          ${datasetId}::uuid,
          ${jurisdiction}::varchar
        ) as preview
      `;
      const value = rows[0]?.preview;
      if (!value || typeof value !== "object") {
        throw new Error("research_preview_result_invalid");
      }
      return value as Record<string, unknown>;
    },

    async listExportJobs(actorAccountId: string, datasetId: string | null) {
      const rows = await sql`
        select * from analytics.list_research_export_jobs(
          ${actorAccountId}::uuid,
          ${datasetId}::uuid
        )
      `;
      return rows.map((row) => ({
        jobId: String(row.job_id),
        datasetId: String(row.dataset_id),
        datasetVersion: Number(row.dataset_version),
        privacyPolicyVersion: Number(row.privacy_policy_version),
        format: String(row.export_format),
        status: String(row.status),
        cohortSize: row.cohort_size == null ? null : Number(row.cohort_size),
        reasonCode: row.reason_code == null ? null : String(row.reason_code),
        artifactSha256: row.artifact_sha256 == null
          ? null
          : String(row.artifact_sha256),
        artifactExpiresAtUtc: row.artifact_expires_at_utc == null
          ? null
          : new Date(String(row.artifact_expires_at_utc)).toISOString(),
        createdAtUtc: new Date(String(row.created_at_utc)).toISOString(),
        updatedAtUtc: new Date(String(row.updated_at_utc)).toISOString(),
      }));
    },

    async getExportDownloadMetadata(actorAccountId: string, jobId: string) {
      const rows = await sql`
        select * from analytics.get_research_export_download(
          ${actorAccountId}::uuid,
          ${jobId}::uuid
        )
      `;
      const row = rows[0];
      if (!row) {
        throw new ApiError(
          404,
          "research_export_download_unavailable",
          "Research export is unavailable or expired.",
        );
      }
      return {
        objectPath: String(row.storage_object_path),
        artifactSha256: String(row.artifact_sha256),
        format: String(row.export_format),
        artifactExpiresAtUtc: new Date(String(row.artifact_expires_at_utc))
          .toISOString(),
      };
    },

    async create(input: {
      actorAccountId: string;
      name: string;
      datasetKind: ResearchDatasetKind;
      purpose: string;
      sourceCategory: string;
      filters: Record<string, unknown>;
      ageBucketYears: number | null;
      minimumCohortSize: number;
      smallCellThreshold: number;
      quasiIdentifierRules: Record<string, unknown>;
      rowMode: "Aggregate" | "Pseudonymous";
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      return await consumeIdempotency({
        sql,
        actorAccountId: input.actorAccountId,
        operation: "research.dataset.create",
        idempotencyKey: input.idempotencyKey,
        requestHash: input.requestHash,
        work: async (tx) => {
          const rows = await tx`
            select analytics.create_research_dataset(
              ${input.actorAccountId}::uuid,
              ${input.name}::varchar,
              ${input.datasetKind}::varchar,
              ${input.purpose}::varchar,
              ${input.sourceCategory}::varchar,
              ${tx.json(input.filters)},
              ${input.ageBucketYears}::smallint,
              ${input.minimumCohortSize}::integer,
              ${input.smallCellThreshold}::integer,
              ${tx.json(input.quasiIdentifierRules)},
              ${input.rowMode}::varchar,
              ${input.correlationId}::uuid
            ) as dataset_id
          `;
          return { datasetId: String(rows[0]?.dataset_id) };
        },
      });
    },

    async requestExport(input: {
      actorAccountId: string;
      datasetId: string;
      format: "CSV" | "XLSX";
      jurisdiction: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      return await consumeIdempotency({
        sql,
        actorAccountId: input.actorAccountId,
        operation: "research.dataset.export.request",
        idempotencyKey: input.idempotencyKey,
        requestHash: input.requestHash,
        work: async (tx) => {
          const rows = await tx`
            select analytics.request_research_export(
              ${input.actorAccountId}::uuid,
              ${input.datasetId}::uuid,
              ${input.format}::varchar,
              ${input.correlationId}::uuid,
              ${input.jurisdiction}::varchar
            ) as job_id
          `;
          const jobId = rows[0]?.job_id;
          if (typeof jobId !== "string") {
            throw new Error("research_export_request_result_invalid");
          }
          return {
            jobId,
            datasetId: input.datasetId,
            format: input.format,
            status: "Pending",
          };
        },
      });
    },
  };
}
