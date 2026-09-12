import { KPI_DEFINITIONS } from "./analytics_catalog.ts";
import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { ExperimentDefinition, ExperimentVariant } from "./experiments.ts";
import type {
  CreateExperimentPayload,
  ExperimentStatusPayload,
} from "./experiments_payload.ts";
import { ApiError } from "./validation.ts";

type ExperimentRow = {
  experiment_key: string;
  name: string;
  control_key: string;
  surface_code: string;
  product_code: string | null;
  segment_key: string | null;
  segment_snapshot_id: string | null;
  primary_metric_code: string;
  guardrail_metric_codes: string[];
  status: ExperimentDefinition["status"];
  starts_at_utc: Date | string | null;
  ends_at_utc: Date | string | null;
  version: number | string;
  created_at_utc: Date | string;
  updated_at_utc: Date | string;
};

type VariantRow = {
  experiment_key: string;
  variant_key: string;
  weight_basis_points: number | string;
  control_value: unknown;
  version: number | string;
};

type ExposureRow = {
  variant_key: string;
  exposure_count: number | string;
  last_exposure_at_utc: Date | string | null;
};

function iso(value: Date | string | null): string | null {
  if (value == null) return null;
  return value instanceof Date
    ? value.toISOString()
    : new Date(value).toISOString();
}

function assertMutationResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "experiment_workflow_unavailable",
      "Experiment workflow result was unavailable.",
    );
  }
  const result = value as Record<string, unknown>;
  if (!Number.isInteger(result.httpStatus) || typeof result.code !== "string") {
    throw new ApiError(
      503,
      "experiment_workflow_unavailable",
      "Experiment workflow result was invalid.",
    );
  }
  return result;
}

function metricAvailability(code: string) {
  const metric = KPI_DEFINITIONS.find((item) => item.name === code);
  return metric
    ? {
      code,
      definitionVersion: metric.definitionVersion,
      availability: metric.availability,
      sourceEvents: metric.eventSources,
      freshnessRule: metric.freshnessRule,
    }
    : {
      code,
      definitionVersion: null,
      availability: "unavailable" as const,
      sourceEvents: [],
      freshnessRule: "Metric is not present in the canonical KPI dictionary.",
    };
}

async function loadVariants(
  sql: AdminSql,
  experimentKeys: string[],
): Promise<Map<string, ExperimentVariant[]>> {
  const result = new Map<string, ExperimentVariant[]>();
  if (experimentKeys.length === 0) return result;
  const rows = await sql<VariantRow[]>`
    select experiment_key,variant_key,weight_basis_points,control_value,version
    from analytics.experiment_variants
    where experiment_key=any(${experimentKeys}::varchar[])
    order by experiment_key,variant_key
  `;
  for (const row of rows) {
    const items = result.get(row.experiment_key) ?? [];
    items.push({
      key: row.variant_key,
      weightBasisPoints: Number(row.weight_basis_points),
      controlValue: row.control_value,
      version: Number(row.version),
    });
    result.set(row.experiment_key, items);
  }
  return result;
}

function mapExperiment(row: ExperimentRow, variants: ExperimentVariant[]) {
  return {
    key: row.experiment_key,
    name: row.name,
    controlKey: row.control_key,
    surface: row.surface_code,
    productCode: row.product_code,
    segmentKey: row.segment_key,
    segmentSnapshotId: row.segment_snapshot_id,
    primaryMetricCode: row.primary_metric_code,
    guardrailMetricCodes: row.guardrail_metric_codes ?? [],
    status: row.status,
    startsAtUtc: iso(row.starts_at_utc),
    endsAtUtc: iso(row.ends_at_utc),
    version: Number(row.version),
    variants,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
    measurement: {
      primary: metricAvailability(row.primary_metric_code),
      guardrails: (row.guardrail_metric_codes ?? []).map(metricAvailability),
      outcomesComputed: false,
      note:
        "Experiment exposure facts are canonical; outcome lift is not computed until a reviewed metric-to-exposure join exists.",
    },
  };
}

export function createExperimentStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async list() {
      const rows = await sql<ExperimentRow[]>`
        select experiment_key,name,control_key,surface_code,product_code,segment_key,segment_snapshot_id,
          primary_metric_code,guardrail_metric_codes,status,starts_at_utc,ends_at_utc,
          version,created_at_utc,updated_at_utc
        from analytics.experiments
        order by updated_at_utc desc,experiment_key
        limit 200
      `;
      const variants = await loadVariants(
        sql,
        rows.map((row) => row.experiment_key),
      );
      return rows.map((row) =>
        mapExperiment(row, variants.get(row.experiment_key) ?? [])
      );
    },

    async get(key: string) {
      const rows = await sql<ExperimentRow[]>`
        select experiment_key,name,control_key,surface_code,product_code,segment_key,segment_snapshot_id,
          primary_metric_code,guardrail_metric_codes,status,starts_at_utc,ends_at_utc,
          version,created_at_utc,updated_at_utc
        from analytics.experiments where experiment_key=${key} limit 1
      `;
      if (rows.length === 0) return null;
      const variants = await loadVariants(sql, [key]);
      const exposures = await sql<ExposureRow[]>`
        select variant_key,count(*)::integer as exposure_count,max(occurred_at_utc) as last_exposure_at_utc
        from analytics.experiment_exposures where experiment_key=${key}
        group by variant_key order by variant_key
      `;
      return {
        ...mapExperiment(rows[0], variants.get(key) ?? []),
        exposureSummary: {
          total: exposures.reduce(
            (sum, row) => sum + Number(row.exposure_count),
            0,
          ),
          variants: exposures.map((row) => ({
            variantKey: row.variant_key,
            count: Number(row.exposure_count),
            lastExposureAtUtc: iso(row.last_exposure_at_utc),
          })),
        },
      };
    },

    async create(input: {
      actorAccountId: string;
      payload: CreateExperimentPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.create_experiment(
          ${input.actorAccountId}::uuid,${p.experimentKey}::varchar,${p.name}::varchar,
          ${p.controlKey}::varchar,${p.surface}::varchar,${p.productCode}::varchar,
          ${p.segmentKey}::varchar,${p.segmentSnapshotId}::uuid,${p.primaryMetricCode}::varchar,
          ${p.guardrailMetricCodes}::varchar[],${
        JSON.stringify(p.variants)
      }::jsonb,
          ${p.startsAtUtc}::timestamptz,${p.endsAtUtc}::timestamptz,${p.reason}::varchar,
          ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },

    async setStatus(input: {
      actorAccountId: string;
      experimentKey: string;
      payload: ExperimentStatusPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.set_experiment_status(
          ${input.actorAccountId}::uuid,${input.experimentKey}::varchar,
          ${input.payload.status}::varchar,${input.payload.expectedVersion}::bigint,
          ${input.payload.reason}::varchar,${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return assertMutationResult(rows[0]?.result);
    },
  };
}
