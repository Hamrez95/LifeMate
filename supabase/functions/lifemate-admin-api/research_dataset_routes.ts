import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { parseResearchDatasetFilters } from "./research_dataset_filters.ts";
import { json } from "./http.ts";
import { createResearchExportSignerFromEnvironment } from "./research_export_signer.ts";
import {
  rejectDirectIdentifierFields,
  validateResearchPrivacyPolicy,
} from "./research_dataset_policy.ts";
import {
  createResearchDatasetStore,
  type ResearchDatasetKind,
} from "./research_dataset_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

const PURPOSE_CODE = /^[a-z][a-z0-9._-]{2,79}$/;
const SOURCE_CATEGORY = /^[A-Za-z][A-Za-z0-9_-]{2,79}$/;
const FIELD_SELECTOR_KEYS = new Set(["field", "attribute", "column", "key"]);
const DATASET_KINDS = new Set<ResearchDatasetKind>([
  "HealthObservationAggregate",
  "DoseAdherenceAggregate",
  "TreatmentAggregate",
  "WomenCycleAggregate",
]);
const UUID =
  "[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";

export function createResearchDatasetRouteHandler(databaseUrl: string) {
  const store = createResearchDatasetStore(databaseUrl);
  const signer = createResearchExportSignerFromEnvironment();
  return async function researchDatasetRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    const downloadMatch = path.match(
      new RegExp(`^/api/v1/research/exports/(${UUID})/download$`, "i"),
    );
    if (downloadMatch && request.method === "GET") {
      requireFounder(admin);
      const jobId = downloadMatch[1].toLowerCase();
      const metadata = await store.getExportDownloadMetadata(accountId, jobId);
      if (!signer) {
        throw new ApiError(
          503,
          "research_export_signer_unavailable",
          "Research export download is not configured.",
        );
      }
      const signed = await signer.sign(accountId, jobId);
      return json(
        {
          jobId,
          format: metadata.format,
          artifactSha256: metadata.artifactSha256,
          artifactExpiresAtUtc: metadata.artifactExpiresAtUtc,
          ...signed,
        },
        200,
        origin,
      );
    }

    const exportMatch = path.match(
      new RegExp(`^/api/v1/research/datasets/(${UUID})/exports$`, "i"),
    );
    if (exportMatch && request.method === "GET") {
      requireFounder(admin);
      const datasetId = exportMatch[1].toLowerCase();
      return json(
        {
          items: await store.listExportJobs(accountId, datasetId),
          access: "founder_only",
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }
    if (exportMatch && request.method === "POST") {
      requireFounder(admin);
      const idempotencyKey = requireIdempotencyKey(request);
      const body = await request.json().catch(() => null);
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        throw new ApiError(
          400,
          "research_export_payload_invalid",
          "Research export payload must be an object.",
        );
      }
      const raw = body as Record<string, unknown>;
      const allowed = new Set(["format"]);
      if (Object.keys(raw).some((key) => !allowed.has(key))) {
        throw new ApiError(
          400,
          "research_export_payload_invalid",
          "Research export payload contains unsupported fields.",
        );
      }
      const format = exportFormat(raw.format);
      const datasetId = exportMatch[1].toLowerCase();
      const jurisdiction = "GLOBAL";
      const canonical = JSON.stringify({ datasetId, format, jurisdiction });
      return json(
        await store.requestExport({
          actorAccountId: accountId,
          datasetId,
          format,
          jurisdiction,
          correlationId,
          idempotencyKey,
          requestHash: await sha256Hex(canonical),
        }),
        202,
        origin,
      );
    }

    const previewMatch = path.match(
      new RegExp(`^/api/v1/research/datasets/(${UUID})/preview$`, "i"),
    );
    if (previewMatch && request.method === "GET") {
      requireFounder(admin);
      return json(
        {
          preview: await store.preview(
            accountId,
            previewMatch[1].toLowerCase(),
          ),
          access: "founder_only",
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (path !== "/api/v1/research/datasets") return null;
    requireFounder(admin);

    if (request.method === "GET") {
      return json(
        {
          items: await store.list(accountId),
          access: "founder_only",
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "POST") {
      const idempotencyKey = requireIdempotencyKey(request);
      const body = await request.json().catch(() => null);
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        throw new ApiError(
          400,
          "research_dataset_payload_invalid",
          "Research dataset payload must be an object.",
        );
      }
      const raw = body as Record<string, unknown>;
      const name = boundedText(raw.name, "name", 160);
      const datasetKind = datasetKindCode(raw.datasetKind);
      const purpose = purposeCode(raw.purpose);
      const sourceCategory = sourceCategoryCode(raw.sourceCategory);
      const rawFilters = boundedObject(raw.filters, "filters");
      const quasiIdentifierRules = boundedObject(
        raw.quasiIdentifierRules,
        "quasiIdentifierRules",
      );
      rejectDirectIdentifierFields([
        ...objectPaths(rawFilters),
        ...objectPaths(quasiIdentifierRules),
        ...fieldReferences(rawFilters),
        ...fieldReferences(quasiIdentifierRules),
      ]);
      const filters = parseResearchDatasetFilters(datasetKind, rawFilters);
      rejectDirectIdentifierFields([
        ...objectPaths(filters),
        ...objectPaths(quasiIdentifierRules),
        ...fieldReferences(filters),
        ...fieldReferences(quasiIdentifierRules),
      ]);
      const privacy = validateResearchPrivacyPolicy({
        ageBucketYears: optionalInteger(raw.ageBucketYears),
        minimumCohortSize: requiredInteger(raw.minimumCohortSize),
        smallCellThreshold: requiredInteger(raw.smallCellThreshold),
        rowMode: rowMode(raw.rowMode),
      });
      const canonical = JSON.stringify({
        name,
        datasetKind,
        purpose,
        sourceCategory,
        filters,
        ageBucketYears: privacy.ageBucketYears,
        minimumCohortSize: privacy.minimumCohortSize,
        smallCellThreshold: privacy.smallCellThreshold,
        quasiIdentifierRules,
        rowMode: privacy.rowMode,
      });
      const result = await store.create({
        actorAccountId: accountId,
        name,
        datasetKind,
        purpose,
        sourceCategory,
        filters,
        ageBucketYears: privacy.ageBucketYears,
        minimumCohortSize: privacy.minimumCohortSize,
        smallCellThreshold: privacy.smallCellThreshold,
        quasiIdentifierRules,
        rowMode: privacy.rowMode,
        correlationId,
        idempotencyKey,
        requestHash: await sha256Hex(canonical),
      });
      return json(result, 201, origin);
    }
    return null;
  };
}

function requireFounder(admin: AdminCapabilitySnapshot) {
  if (!admin.roles.includes("founder")) {
    throw new ApiError(
      403,
      "research_founder_required",
      "Founder role is required for Research Studio.",
    );
  }
}

function boundedText(value: unknown, field: string, max: number): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      `${field} is required.`,
    );
  }
  const text = value.trim();
  if (text.length < 3 || text.length > max) {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      `${field} is invalid.`,
    );
  }
  return text;
}

function datasetKindCode(value: unknown): ResearchDatasetKind {
  if (
    typeof value !== "string" ||
    !DATASET_KINDS.has(value as ResearchDatasetKind)
  ) {
    throw new ApiError(
      400,
      "research_dataset_kind_invalid",
      "datasetKind is invalid.",
    );
  }
  return value as ResearchDatasetKind;
}

function purposeCode(value: unknown): string {
  if (typeof value !== "string" || !PURPOSE_CODE.test(value.trim())) {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      "purpose is invalid.",
    );
  }
  return value.trim();
}

function sourceCategoryCode(value: unknown): string {
  if (typeof value !== "string" || !SOURCE_CATEGORY.test(value.trim())) {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      "sourceCategory is invalid.",
    );
  }
  return value.trim();
}

function boundedObject(value: unknown, field: string): Record<string, unknown> {
  if (value == null) return {};
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      `${field} must be an object.`,
    );
  }
  const object = value as Record<string, unknown>;
  if (new TextEncoder().encode(JSON.stringify(object)).byteLength > 16_000) {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      `${field} is too large.`,
    );
  }
  return object;
}

function objectPaths(value: Record<string, unknown>, prefix = ""): string[] {
  const result: string[] = [];
  for (const [key, child] of Object.entries(value)) {
    const itemPath = prefix ? `${prefix}.${key}` : key;
    result.push(itemPath);
    if (child && typeof child === "object" && !Array.isArray(child)) {
      result.push(...objectPaths(child as Record<string, unknown>, itemPath));
    }
  }
  return result;
}

function fieldReferences(value: unknown): string[] {
  if (Array.isArray(value)) return value.flatMap(fieldReferences);
  if (!value || typeof value !== "object") return [];
  const result: string[] = [];
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (
      FIELD_SELECTOR_KEYS.has(key.toLowerCase()) && typeof child === "string"
    ) {
      result.push(child.trim());
    }
    result.push(...fieldReferences(child));
  }
  return result;
}

function optionalInteger(value: unknown): number | null {
  if (value == null) return null;
  if (!Number.isInteger(value)) {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      "ageBucketYears must be an integer.",
    );
  }
  return Number(value);
}

function requiredInteger(value: unknown): number {
  if (!Number.isInteger(value)) {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      "Privacy thresholds must be integers.",
    );
  }
  return Number(value);
}

function rowMode(value: unknown): "Aggregate" | "Pseudonymous" {
  if (value !== "Aggregate" && value !== "Pseudonymous") {
    throw new ApiError(
      400,
      "research_dataset_payload_invalid",
      "rowMode is invalid.",
    );
  }
  return value;
}

function exportFormat(value: unknown): "CSV" | "XLSX" {
  if (value !== "CSV" && value !== "XLSX") {
    throw new ApiError(
      400,
      "research_export_format_invalid",
      "format must be CSV or XLSX.",
    );
  }
  return value;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}
