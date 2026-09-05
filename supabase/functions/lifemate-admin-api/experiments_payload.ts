import {
  assertExperimentMetrics,
  assertVariantWeights,
  type ExperimentStatus,
  type ExperimentVariant,
  parseExperimentKey,
  parseExperimentSurface,
} from "./experiments.ts";
import { ApiError } from "./validation.ts";

export type CreateExperimentPayload = {
  experimentKey: string;
  name: string;
  controlKey: string;
  surface: ReturnType<typeof parseExperimentSurface>;
  productCode: string | null;
  segmentKey: string | null;
  segmentSnapshotId: string | null;
  primaryMetricCode: string;
  guardrailMetricCodes: string[];
  variants: ExperimentVariant[];
  startsAtUtc: string | null;
  endsAtUtc: string | null;
  reason: string;
};

export type ExperimentStatusPayload = {
  status: Exclude<ExperimentStatus, "Draft">;
  expectedVersion: number;
  reason: string;
};

const TARGET_KEY = /^[a-z0-9][a-z0-9._:-]{0,95}$/;
const METRIC_KEY = /^[a-z][a-z0-9._-]{2,95}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function objectBody(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ApiError(
      400,
      "experiment_payload_invalid",
      "Experiment payload must be an object.",
    );
  }
  return input as Record<string, unknown>;
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    return objectBody(await request.json());
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON.");
  }
}

function requiredText(
  value: unknown,
  field: string,
  min: number,
  max: number,
): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "experiment_payload_invalid",
      `${field} is required.`,
    );
  }
  const text = value.trim();
  if (text.length < min || text.length > max) {
    throw new ApiError(
      400,
      "experiment_payload_invalid",
      `${field} is invalid.`,
    );
  }
  return text;
}

function optionalTarget(value: unknown, field: string): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "experiment_payload_invalid",
      `${field} is invalid.`,
    );
  }
  const normalized = value.trim().toLowerCase();
  if (!TARGET_KEY.test(normalized)) {
    throw new ApiError(
      400,
      "experiment_payload_invalid",
      `${field} is invalid.`,
    );
  }
  return normalized;
}

function optionalUuid(value: unknown, field: string): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || !UUID.test(value.trim())) {
    throw new ApiError(
      400,
      "experiment_payload_invalid",
      `${field} is invalid.`,
    );
  }
  return value.trim().toLowerCase();
}

function metricCode(value: unknown, field: string): string {
  const code = requiredText(value, field, 3, 96).toLowerCase();
  if (!METRIC_KEY.test(code)) {
    throw new ApiError(
      400,
      "experiment_metric_unknown",
      `${field} is invalid.`,
    );
  }
  return code;
}

function parseDate(value: unknown, field: string): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "experiment_payload_invalid",
      `${field} is invalid.`,
    );
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date.toISOString() !== value) {
    throw new ApiError(
      400,
      "experiment_payload_invalid",
      `${field} must be a canonical UTC ISO timestamp.`,
    );
  }
  return value;
}

function parseVariants(value: unknown): ExperimentVariant[] {
  if (!Array.isArray(value)) {
    throw new ApiError(
      400,
      "experiment_variants_invalid",
      "Experiment variants are required.",
    );
  }
  const variants = value.map((row): ExperimentVariant => {
    const item = objectBody(row);
    const key = parseExperimentKey(
      requiredText(item.key, "variant.key", 3, 96),
    );
    if (!Number.isInteger(item.weightBasisPoints)) {
      throw new ApiError(
        400,
        "experiment_variant_weight_invalid",
        "Variant weight must be an integer basis-point value.",
      );
    }
    if (!Number.isInteger(item.version) || Number(item.version) < 1) {
      throw new ApiError(
        400,
        "experiment_variant_version_invalid",
        "Variant version must be a positive integer.",
      );
    }
    if (!("controlValue" in item) || item.controlValue === undefined) {
      throw new ApiError(
        400,
        "experiment_variant_value_missing",
        "Variant control value is required.",
      );
    }
    const controlValue = item.controlValue;
    const serialized = JSON.stringify(controlValue);
    if (
      serialized === undefined ||
      new TextEncoder().encode(serialized).byteLength > 4096
    ) {
      throw new ApiError(
        400,
        "experiment_variant_value_too_large",
        "Variant control value is invalid or too large.",
      );
    }
    return {
      key,
      weightBasisPoints: Number(item.weightBasisPoints),
      controlValue,
      version: Number(item.version),
    };
  });
  assertVariantWeights(variants);
  return variants;
}

export async function parseCreateExperimentPayload(
  request: Request,
): Promise<CreateExperimentPayload> {
  const body = await readJson(request);
  const primaryMetricCode = metricCode(
    body.primaryMetricCode,
    "primaryMetricCode",
  );
  const guardrailMetricCodes = Array.isArray(body.guardrailMetricCodes)
    ? body.guardrailMetricCodes.map((value) =>
      metricCode(value, "guardrailMetricCodes")
    )
    : [];
  assertExperimentMetrics(primaryMetricCode, guardrailMetricCodes);

  const startsAtUtc = parseDate(body.startsAtUtc, "startsAtUtc");
  const endsAtUtc = parseDate(body.endsAtUtc, "endsAtUtc");
  if (startsAtUtc && endsAtUtc && endsAtUtc <= startsAtUtc) {
    throw new ApiError(
      400,
      "experiment_window_invalid",
      "Experiment end must be after start.",
    );
  }

  const segmentKey = optionalTarget(body.segmentKey, "segmentKey");
  const segmentSnapshotId = optionalUuid(
    body.segmentSnapshotId,
    "segmentSnapshotId",
  );
  if ((segmentKey == null) !== (segmentSnapshotId == null)) {
    throw new ApiError(
      400,
      "experiment_segment_snapshot_required",
      "Segment-targeted experiments require both segmentKey and segmentSnapshotId.",
    );
  }

  return {
    experimentKey: parseExperimentKey(
      requiredText(body.experimentKey, "experimentKey", 3, 96),
    ),
    name: requiredText(body.name, "name", 3, 160),
    controlKey: parseExperimentKey(
      requiredText(body.controlKey, "controlKey", 3, 96),
    ),
    surface: parseExperimentSurface(body.surface),
    productCode: optionalTarget(body.productCode, "productCode"),
    segmentKey,
    segmentSnapshotId,
    primaryMetricCode,
    guardrailMetricCodes,
    variants: parseVariants(body.variants),
    startsAtUtc,
    endsAtUtc,
    reason: requiredText(body.reason, "reason", 10, 1000),
  };
}

export async function parseExperimentStatusPayload(
  request: Request,
): Promise<ExperimentStatusPayload> {
  const body = await readJson(request);
  const allowed = new Set<ExperimentStatus>([
    "Scheduled",
    "Running",
    "Paused",
    "Stopped",
    "Completed",
  ]);
  if (
    typeof body.status !== "string" ||
    !allowed.has(body.status as ExperimentStatus)
  ) {
    throw new ApiError(
      400,
      "experiment_status_invalid",
      "Experiment status is invalid.",
    );
  }
  if (
    !Number.isSafeInteger(body.expectedVersion) ||
    Number(body.expectedVersion) < 1
  ) {
    throw new ApiError(
      400,
      "experiment_version_invalid",
      "Expected version must be a positive safe integer.",
    );
  }
  return {
    status: body.status as ExperimentStatusPayload["status"],
    expectedVersion: Number(body.expectedVersion),
    reason: requiredText(body.reason, "reason", 10, 1000),
  };
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${
      Object.keys(record).sort().map((key) =>
        `${JSON.stringify(key)}:${canonical(record[key])}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value);
}

export async function hashExperimentMutation(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(canonical(value));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest).map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
