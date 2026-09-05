import {
  selectWeightedExperimentVariant,
  stableExperimentBucket,
  type WeightedExperimentVariant,
} from "../_shared/experiment_assignment.ts";
import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type RawExperiment = {
  key: string;
  controlKey: string;
  surface: string;
  productCode: string | null;
  experimentVersion: number;
  valueType: string;
  variants: WeightedExperimentVariant[];
};

const PRODUCT = /^[a-z0-9][a-z0-9._:-]{0,63}$/;

export function parseExperimentAssignmentProduct(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "experiment_product_invalid",
      "product is required.",
    );
  }
  const product = value.trim().toLowerCase();
  if (!PRODUCT.test(product)) {
    throw new ApiError(
      400,
      "experiment_product_invalid",
      "product is invalid.",
    );
  }
  return product;
}

function asRawExperiments(value: unknown): RawExperiment[] {
  if (!Array.isArray(value)) {
    throw new ApiError(
      503,
      "experiment_assignment_unavailable",
      "Experiment assignment source was unavailable.",
    );
  }
  return value.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new ApiError(
        503,
        "experiment_assignment_unavailable",
        "Experiment assignment source was invalid.",
      );
    }
    const row = item as Record<string, unknown>;
    if (
      typeof row.key !== "string" ||
      typeof row.controlKey !== "string" ||
      typeof row.surface !== "string" ||
      !Number.isSafeInteger(row.experimentVersion) ||
      typeof row.valueType !== "string" ||
      !Array.isArray(row.variants)
    ) {
      throw new ApiError(
        503,
        "experiment_assignment_unavailable",
        "Experiment assignment source was invalid.",
      );
    }
    const variants = row.variants.map((variant): WeightedExperimentVariant => {
      if (!variant || typeof variant !== "object" || Array.isArray(variant)) {
        throw new ApiError(
          503,
          "experiment_assignment_unavailable",
          "Experiment variant was invalid.",
        );
      }
      const v = variant as Record<string, unknown>;
      if (
        typeof v.key !== "string" ||
        !Number.isInteger(v.weightBasisPoints) ||
        !Number.isSafeInteger(v.version) ||
        !("controlValue" in v)
      ) {
        throw new ApiError(
          503,
          "experiment_assignment_unavailable",
          "Experiment variant was invalid.",
        );
      }
      return {
        key: v.key,
        weightBasisPoints: Number(v.weightBasisPoints),
        controlValue: v.controlValue,
        version: Number(v.version),
      };
    });
    const total = variants.reduce(
      (sum, variant) => sum + variant.weightBasisPoints,
      0,
    );
    if (variants.length < 2 || variants.length > 10 || total !== 10_000) {
      throw new ApiError(
        503,
        "experiment_assignment_unavailable",
        "Experiment weights were invalid.",
      );
    }
    return {
      key: row.key,
      controlKey: row.controlKey,
      surface: row.surface,
      productCode: row.productCode == null ? null : String(row.productCode),
      experimentVersion: Number(row.experimentVersion),
      valueType: row.valueType,
      variants,
    };
  });
}

async function hmacHex(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value)),
  );
  return Array.from(signature).map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function createExperimentAssignmentStore(
  databaseUrl: string,
  hashingSecret: string,
) {
  const sql = getLifeMateSql(databaseUrl);
  if (hashingSecret.length < 32) {
    throw new Error(
      "Experiment subject hashing secret is not configured safely.",
    );
  }

  return {
    async assignAndRecord(appUserId: string, product: string) {
      const rows = await sql`
        select analytics.get_eligible_experiments(
          ${appUserId}::uuid,
          ${product}::varchar
        ) as result
      `;
      const experiments = asRawExperiments(rows[0]?.result);
      const subjectKey = `account:${appUserId}`;
      const subjectHash = await hmacHex(
        hashingSecret,
        `experiment-subject:v1:${appUserId}`,
      );
      const now = new Date();
      const assignments = [];

      for (const experiment of experiments) {
        const bucketBasisPoints = await stableExperimentBucket(
          experiment.key,
          subjectKey,
        );
        const variant = selectWeightedExperimentVariant(
          experiment.variants,
          bucketBasisPoints,
        );
        if (!variant) {
          throw new ApiError(
            503,
            "experiment_assignment_unavailable",
            "Experiment assignment could not resolve a variant.",
          );
        }
        const idempotencyHash = await hmacHex(
          hashingSecret,
          `experiment-exposure:v1:${experiment.key}:${experiment.experimentVersion}:${subjectHash}`,
        );
        const exposureRows = await sql`
          select analytics.record_experiment_exposure(
            ${experiment.key}::varchar,
            ${experiment.experimentVersion}::bigint,
            ${variant.key}::varchar,
            ${variant.version}::bigint,
            ${subjectHash}::varchar,
            ${idempotencyHash}::varchar,
            ${now.toISOString()}::timestamptz,
            ${
          JSON.stringify({ productCode: product, surface: experiment.surface })
        }::jsonb
          ) as recorded
        `;
        if (exposureRows[0]?.recorded !== true) {
          throw new ApiError(
            503,
            "experiment_exposure_unavailable",
            "Experiment exposure could not be recorded safely.",
          );
        }
        assignments.push({
          experimentKey: experiment.key,
          experimentVersion: experiment.experimentVersion,
          controlKey: experiment.controlKey,
          valueType: experiment.valueType,
          variantKey: variant.key,
          variantVersion: variant.version,
          value: variant.controlValue,
          bucketBasisPoints,
          authoritative: "server",
        });
      }
      return { assignments, generatedAtUtc: now.toISOString() };
    },
  };
}
