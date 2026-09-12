import { ApiError } from "./validation.ts";

export type ResearchPrivacyPolicy = {
  ageBucketYears: number | null;
  minimumCohortSize: number;
  smallCellThreshold: number;
  rowMode: "Aggregate" | "Pseudonymous";
};

export function validateResearchPrivacyPolicy(input: ResearchPrivacyPolicy) {
  if (
    input.ageBucketYears !== null &&
    (!Number.isInteger(input.ageBucketYears) || input.ageBucketYears < 1 ||
      input.ageBucketYears > 20)
  ) {
    throw new ApiError(
      400,
      "research_age_bucket_invalid",
      "Age bucket size is invalid.",
    );
  }
  if (
    !Number.isInteger(input.minimumCohortSize) || input.minimumCohortSize < 5 ||
    input.minimumCohortSize > 1_000_000
  ) {
    throw new ApiError(
      400,
      "research_cohort_threshold_invalid",
      "Minimum cohort size is invalid.",
    );
  }
  if (
    !Number.isInteger(input.smallCellThreshold) ||
    input.smallCellThreshold < 5 ||
    input.smallCellThreshold > input.minimumCohortSize
  ) {
    throw new ApiError(
      400,
      "research_small_cell_threshold_invalid",
      "Small-cell threshold is invalid.",
    );
  }
  if (input.rowMode !== "Aggregate" && input.rowMode !== "Pseudonymous") {
    throw new ApiError(
      400,
      "research_row_mode_invalid",
      "Research row mode is invalid.",
    );
  }
  if (input.rowMode === "Pseudonymous") {
    throw new ApiError(
      409,
      "research_pseudonymous_export_unavailable",
      "Pseudonymous row-level research export is not available yet.",
    );
  }
  return input;
}

export function ageBucketLabel(age: number, width: number): string {
  if (!Number.isInteger(age) || age < 0 || age > 130) {
    throw new ApiError(
      400,
      "research_age_invalid",
      "Age is outside the supported range.",
    );
  }
  if (!Number.isInteger(width) || width < 1 || width > 20) {
    throw new ApiError(
      400,
      "research_age_bucket_invalid",
      "Age bucket size is invalid.",
    );
  }
  const endInclusive = age === 0 ? width : Math.ceil(age / width) * width;
  const startExclusive = Math.max(0, endInclusive - width);
  return `${startExclusive}–${endInclusive}`;
}

export function suppressSmallCells<T extends { count: number }>(
  cells: T[],
  threshold: number,
): Array<T & { suppressed: boolean }> {
  if (!Number.isInteger(threshold) || threshold < 5) {
    throw new ApiError(
      400,
      "research_small_cell_threshold_invalid",
      "Small-cell threshold is invalid.",
    );
  }
  return cells.map((cell) => ({
    ...cell,
    suppressed: !Number.isFinite(cell.count) || cell.count < threshold,
  }));
}

export function assertCohortExportable(
  cohortSize: number,
  policy: ResearchPrivacyPolicy,
) {
  validateResearchPrivacyPolicy(policy);
  if (!Number.isInteger(cohortSize) || cohortSize < policy.minimumCohortSize) {
    throw new ApiError(
      409,
      "research_cohort_too_small",
      "Dataset cohort does not meet the privacy threshold.",
    );
  }
}

export function rejectDirectIdentifierFields(fields: string[]) {
  const forbiddenTokens = new Set([
    "email",
    "emailaddress",
    "phone",
    "phonenumber",
    "mobile",
    "mobilenumber",
    "name",
    "fullname",
    "address",
    "nationalid",
    "contact",
    "contactpoint",
    "token",
    "externalid",
    "personid",
    "accountid",
    "appuserid",
    "authuserid",
    "userid",
  ]);
  const match = fields.find((field) => {
    const tokens = field
      .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter(Boolean);
    if (tokens.some((token) => forbiddenTokens.has(token))) return true;
    const compact = tokens.join("");
    return forbiddenTokens.has(compact);
  });
  if (match) {
    throw new ApiError(
      400,
      "research_direct_identifier_forbidden",
      "Direct or linkable identifiers cannot be exported in a research dataset.",
    );
  }
}
