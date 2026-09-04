import {
  formatResearchPreview,
  type ResearchExportFormat,
} from "./research_export_format.ts";

export type ResearchExportClaim = {
  jobId: string;
  datasetId: string;
  datasetVersion: number;
  privacyPolicyVersion: number;
  format: ResearchExportFormat;
  requestedByAccountId: string;
  preview: Record<string, unknown>;
};

export interface ResearchExportStore {
  claim(jobId: string): Promise<ResearchExportClaim | null>;
  complete(input: {
    jobId: string;
    objectPath: string;
    sha256: string;
    expiresAtUtc: string;
  }): Promise<boolean>;
  fail(jobId: string, reasonCode: string): Promise<boolean>;
}

export interface ResearchExportArtifactStorage {
  upload(input: {
    jobId: string;
    extension: "csv" | "xlsx";
    contentType: string;
    bytes: Uint8Array;
  }): Promise<string>;
}

export async function processResearchExport(input: {
  jobId: string;
  store: ResearchExportStore;
  storage: ResearchExportArtifactStorage;
  now?: () => Date;
}): Promise<"completed" | "noop" | "failed"> {
  const claim = await input.store.claim(input.jobId);
  if (!claim) return "noop";

  let formatted;
  try {
    formatted = formatResearchPreview(claim.preview, claim.format);
  } catch (error) {
    const reason = permanentFormatReason(error);
    await input.store.fail(claim.jobId, reason);
    return "failed";
  }

  const objectPath = await input.storage.upload({
    jobId: claim.jobId,
    extension: formatted.extension,
    contentType: formatted.contentType,
    bytes: formatted.bytes,
  });
  const sha256 = await sha256Hex(formatted.bytes);
  const now = input.now?.() ?? new Date();
  const expiresAtUtc = new Date(now.getTime() + 24 * 60 * 60_000).toISOString();
  const completed = await input.store.complete({
    jobId: claim.jobId,
    objectPath,
    sha256,
    expiresAtUtc,
  });
  if (!completed) {
    throw new Error("research_export_complete_transition_failed");
  }
  return "completed";
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    Uint8Array.from(bytes).buffer,
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

function permanentFormatReason(error: unknown): string {
  const raw = error instanceof Error
    ? error.message
    : "research_export_format_failed";
  const normalized = raw.toLowerCase().replace(/[^a-z0-9_.-]/g, "_");
  return /^[a-z][a-z0-9_.-]{2,99}$/.test(normalized)
    ? normalized
    : "research_export_format_failed";
}
