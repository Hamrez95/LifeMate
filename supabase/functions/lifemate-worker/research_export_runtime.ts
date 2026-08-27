import { createResearchExportStorage } from "./research_export_storage.ts";
import {
  processResearchExport,
  type ResearchExportClaim,
  type ResearchExportStore,
} from "./research_export_worker.ts";

type SqlLike = any;

export function createResearchExportRuntime(
  sql: SqlLike,
  supabaseUrl: string,
  serviceRoleKey: string,
  fetcher: typeof fetch = fetch,
) {
  const storage = createResearchExportStorage(supabaseUrl, serviceRoleKey, fetcher);
  const store: ResearchExportStore = {
    async claim(jobId: string) {
      const rows = await sql`
        select * from analytics.claim_research_export_for_worker(
          ${jobId}::uuid,'GLOBAL'::varchar
        )
      `;
      const row = rows[0];
      if (!row) return null;
      const format = String(row.export_format);
      if (format !== "CSV" && format !== "XLSX") {
        throw new Error("research_export_format_invalid");
      }
      const preview = row.preview_json;
      if (!preview || typeof preview !== "object" || Array.isArray(preview)) {
        throw new Error("research_preview_result_invalid");
      }
      return {
        jobId: String(row.job_id),
        datasetId: String(row.dataset_id),
        datasetVersion: Number(row.dataset_version),
        privacyPolicyVersion: Number(row.privacy_policy_version),
        format,
        requestedByAccountId: String(row.requested_by_account_id),
        preview: preview as Record<string, unknown>,
      } satisfies ResearchExportClaim;
    },

    async complete(input) {
      const rows = await sql`
        select analytics.complete_research_export_for_worker(
          ${input.jobId}::uuid,
          ${input.objectPath}::varchar,
          ${input.sha256}::char(64),
          ${input.expiresAtUtc}::timestamptz
        ) as ok
      `;
      return rows[0]?.ok === true;
    },

    async fail(jobId, reasonCode) {
      const rows = await sql`
        select analytics.fail_research_export_for_worker(
          ${jobId}::uuid,${reasonCode}::varchar
        ) as ok
      `;
      return rows[0]?.ok === true;
    },
  };

  return {
    async process(jobId: string) {
      return await processResearchExport({ jobId, store, storage });
    },
  };
}
