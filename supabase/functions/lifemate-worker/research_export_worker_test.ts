import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  processResearchExport,
  type ResearchExportArtifactStorage,
  type ResearchExportStore,
} from "./research_export_worker.ts";

function claim() {
  return {
    jobId: "00000000-0000-4000-8000-000000000001",
    datasetId: "00000000-0000-4000-8000-000000000002",
    datasetVersion: 2,
    privacyPolicyVersion: 3,
    format: "CSV" as const,
    requestedByAccountId: "00000000-0000-4000-8000-000000000003",
    preview: {
      eligible: true,
      cells: [{ observationType: "weight", subjectCount: 20 }],
    },
  };
}

Deno.test("research export worker publishes only after DB completion", async () => {
  const calls: string[] = [];
  const store: ResearchExportStore = {
    claim: async () => claim(),
    complete: async (input) => {
      calls.push(`complete:${input.objectPath}:${input.sha256.length}`);
      return true;
    },
    fail: async () => false,
  };
  const storage: ResearchExportArtifactStorage = {
    upload: async (input) => {
      calls.push(`upload:${input.jobId}:${input.extension}`);
      return `${input.jobId}.${input.extension}`;
    },
  };
  assertEquals(await processResearchExport({
    jobId: claim().jobId,
    store,
    storage,
    now: () => new Date("2026-08-27T00:00:00Z"),
  }), "completed");
  assertEquals(calls[0], `upload:${claim().jobId}:csv`);
  assertEquals(calls[1]?.startsWith(`complete:${claim().jobId}.csv:64`), true);
});

Deno.test("research export worker throws when artifact exists but DB publish fails", async () => {
  const store: ResearchExportStore = {
    claim: async () => claim(),
    complete: async () => false,
    fail: async () => false,
  };
  const storage: ResearchExportArtifactStorage = {
    upload: async () => `${claim().jobId}.csv`,
  };
  await assertRejects(
    () => processResearchExport({ jobId: claim().jobId, store, storage }),
    Error,
    "research_export_complete_transition_failed",
  );
});

Deno.test("research export worker permanently fails malformed aggregate snapshot", async () => {
  let failedReason = "";
  const store: ResearchExportStore = {
    claim: async () => ({ ...claim(), preview: { eligible: false, cells: [] } }),
    complete: async () => false,
    fail: async (_jobId, reason) => {
      failedReason = reason;
      return true;
    },
  };
  const storage: ResearchExportArtifactStorage = {
    upload: async () => {
      throw new Error("must_not_upload");
    },
  };
  assertEquals(await processResearchExport({ jobId: claim().jobId, store, storage }), "failed");
  assertEquals(failedReason, "research_preview_not_exportable");
});
