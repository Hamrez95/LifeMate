import {
  selectWeightedExperimentVariant,
  stableExperimentBucket,
  type WeightedExperimentVariant,
} from "../_shared/experiment_assignment.ts";
import { KPI_DEFINITIONS } from "./analytics_catalog.ts";
import { ApiError } from "./validation.ts";

export type ExperimentStatus =
  | "Draft"
  | "Scheduled"
  | "Running"
  | "Paused"
  | "Stopped"
  | "Completed";

export type ExperimentSurface =
  | "onboarding"
  | "pricing"
  | "paywall"
  | "cta"
  | "offer"
  | "nonclinical_feature";

export type ExperimentVariant = WeightedExperimentVariant;

export type ExperimentDefinition = {
  key: string;
  name: string;
  controlKey: string;
  surface: ExperimentSurface;
  productCode: string | null;
  segmentKey: string | null;
  primaryMetricCode: string;
  guardrailMetricCodes: string[];
  status: ExperimentStatus;
  startsAtUtc: string | null;
  endsAtUtc: string | null;
  version: number;
  variants: ExperimentVariant[];
};

export type ExperimentAssignmentContext = {
  subjectKey: string;
  productCode?: string | null;
  segmentKeys?: string[];
  now?: Date;
};

export type ExperimentAssignment = {
  eligible: boolean;
  variantKey: string | null;
  variantVersion: number | null;
  controlValue: unknown | null;
  experimentVersion: number;
  bucketBasisPoints: number | null;
  reason:
    | "assigned"
    | "not_running"
    | "outside_window"
    | "product_mismatch"
    | "segment_mismatch";
};

const KEY = /^[a-z][a-z0-9._-]{2,95}$/;
const SUBJECT_KEY = /^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$/;
const SURFACES = new Set<ExperimentSurface>([
  "onboarding",
  "pricing",
  "paywall",
  "cta",
  "offer",
  "nonclinical_feature",
]);

export function parseExperimentKey(value: string): string {
  const key = value.trim().toLowerCase();
  if (!KEY.test(key)) {
    throw new ApiError(
      400,
      "experiment_key_invalid",
      "Experiment key is invalid.",
    );
  }
  return key;
}

export function parseExperimentSurface(value: unknown): ExperimentSurface {
  if (typeof value !== "string" || !SURFACES.has(value as ExperimentSurface)) {
    throw new ApiError(
      400,
      "experiment_surface_invalid",
      "Experiment surface is not supported.",
    );
  }
  return value as ExperimentSurface;
}

export function assertExperimentMetrics(
  primaryMetricCode: string,
  guardrailMetricCodes: string[],
  options: { requireMeasurable?: boolean } = {},
): void {
  const byName = new Map(
    KPI_DEFINITIONS.map((metric) => [metric.name, metric]),
  );
  const primary = byName.get(primaryMetricCode);
  if (!primary) {
    throw new ApiError(
      400,
      "experiment_metric_unknown",
      "Primary metric is not part of the canonical KPI dictionary.",
    );
  }
  if (guardrailMetricCodes.length > 8) {
    throw new ApiError(
      400,
      "experiment_guardrails_too_many",
      "At most 8 guardrail metrics are allowed.",
    );
  }
  if (new Set(guardrailMetricCodes).size !== guardrailMetricCodes.length) {
    throw new ApiError(
      400,
      "experiment_guardrail_duplicate",
      "Guardrail metrics must be unique.",
    );
  }
  for (const code of guardrailMetricCodes) {
    if (!byName.has(code)) {
      throw new ApiError(
        400,
        "experiment_metric_unknown",
        "Guardrail metric is not part of the canonical KPI dictionary.",
      );
    }
    if (code === primaryMetricCode) {
      throw new ApiError(
        400,
        "experiment_metric_duplicate",
        "Primary metric cannot also be a guardrail metric.",
      );
    }
  }

  if (options.requireMeasurable) {
    const unavailable = [primaryMetricCode, ...guardrailMetricCodes].filter(
      (code) => byName.get(code)?.availability === "unavailable",
    );
    if (unavailable.length > 0) {
      throw new ApiError(
        409,
        "experiment_metric_unavailable",
        "Experiment cannot run until every configured metric has canonical measurement support.",
      );
    }
  }
}

export function assertVariantWeights(variants: ExperimentVariant[]): void {
  if (variants.length < 2 || variants.length > 10) {
    throw new ApiError(
      400,
      "experiment_variants_invalid",
      "An experiment requires between 2 and 10 variants.",
    );
  }
  const keys = new Set<string>();
  let total = 0;
  for (const variant of variants) {
    if (!KEY.test(variant.key) || keys.has(variant.key)) {
      throw new ApiError(
        400,
        "experiment_variant_key_invalid",
        "Experiment variant keys must be unique and canonical.",
      );
    }
    if (
      !Number.isInteger(variant.weightBasisPoints) ||
      variant.weightBasisPoints <= 0 ||
      variant.weightBasisPoints > 10_000
    ) {
      throw new ApiError(
        400,
        "experiment_variant_weight_invalid",
        "Variant weights must be positive basis-point integers.",
      );
    }
    if (!Number.isInteger(variant.version) || variant.version < 1) {
      throw new ApiError(
        400,
        "experiment_variant_version_invalid",
        "Variant version must be a positive integer.",
      );
    }
    keys.add(variant.key);
    total += variant.weightBasisPoints;
  }
  if (total !== 10_000) {
    throw new ApiError(
      400,
      "experiment_variant_weight_total_invalid",
      "Variant weights must total exactly 10000 basis points.",
    );
  }
}

function withinWindow(experiment: ExperimentDefinition, now: Date): boolean {
  const start = experiment.startsAtUtc
    ? new Date(experiment.startsAtUtc)
    : null;
  const end = experiment.endsAtUtc ? new Date(experiment.endsAtUtc) : null;
  return (!start || start <= now) && (!end || now < end);
}

export async function assignExperimentVariant(
  experiment: ExperimentDefinition,
  context: ExperimentAssignmentContext,
): Promise<ExperimentAssignment> {
  assertVariantWeights(experiment.variants);
  const now = context.now ?? new Date();

  if (experiment.status !== "Running") {
    return {
      eligible: false,
      variantKey: null,
      variantVersion: null,
      controlValue: null,
      experimentVersion: experiment.version,
      bucketBasisPoints: null,
      reason: "not_running",
    };
  }
  if (!withinWindow(experiment, now)) {
    return {
      eligible: false,
      variantKey: null,
      variantVersion: null,
      controlValue: null,
      experimentVersion: experiment.version,
      bucketBasisPoints: null,
      reason: "outside_window",
    };
  }
  if (
    experiment.productCode && experiment.productCode !== context.productCode
  ) {
    return {
      eligible: false,
      variantKey: null,
      variantVersion: null,
      controlValue: null,
      experimentVersion: experiment.version,
      bucketBasisPoints: null,
      reason: "product_mismatch",
    };
  }
  if (
    experiment.segmentKey &&
    !(context.segmentKeys ?? []).includes(experiment.segmentKey)
  ) {
    return {
      eligible: false,
      variantKey: null,
      variantVersion: null,
      controlValue: null,
      experimentVersion: experiment.version,
      bucketBasisPoints: null,
      reason: "segment_mismatch",
    };
  }
  if (!SUBJECT_KEY.test(context.subjectKey)) {
    throw new ApiError(
      400,
      "experiment_subject_invalid",
      "Experiment subject key is invalid.",
    );
  }

  const bucketBasisPoints = await stableExperimentBucket(
    experiment.key,
    context.subjectKey,
  );
  const variant = selectWeightedExperimentVariant(
    experiment.variants,
    bucketBasisPoints,
  );
  if (!variant) {
    throw new ApiError(
      503,
      "experiment_assignment_invalid",
      "Experiment assignment could not resolve a variant.",
    );
  }
  return {
    eligible: true,
    variantKey: variant.key,
    variantVersion: variant.version,
    controlValue: variant.controlValue,
    experimentVersion: experiment.version,
    bucketBasisPoints,
    reason: "assigned",
  };
}
