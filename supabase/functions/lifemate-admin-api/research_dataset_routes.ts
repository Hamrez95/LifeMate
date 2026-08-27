import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { parseResearchDatasetFilters } from "./research_dataset_filters.ts";
import { json } from "./http.ts";
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

export function createResearchDatasetRouteHandler(databaseUrl: string) {
  const store = createResearchDatasetStore(databaseUrl);
  return async function researchDatasetRoute(context: Context): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;
    if (path !== "/api/v1/research/datasets") return null;
    requireFounder(admin);

    if (request.method === "GET") {
      return json({
        items: await store.list(accountId),
        access: "founder_only",
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "POST") {
      const idempotencyKey = requireIdempotencyKey(request);
      const body = await request.json().catch(() => null);
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        throw new ApiError(400, "research_dataset_payload_invalid", "Research dataset payload must be an object.");
      }
      const raw = body as Record<string, unknown>;
      const name = boundedText(raw.name, "name", 160);
      const datasetKind = datasetKindCode(raw.datasetKind);
      const purpose = purposeCode(raw.purpose);
      const sourceCategory = sourceCategoryCode(raw.sourceCategory);
      const rawFilters = boundedObject(raw.filters, "filters");
      const filters = parseResearchDatasetFilters(datasetKind, rawFilters);
      const quasiIdentifierRules = boundedObject(raw.quasiIdentifierRules, "quasiIdentifierRules");
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
    throw new ApiError(403, "research_founder_required", "Founder role is required for Research Studio.");
  }
}

function boundedText(value: unknown, field: string, max: number): string {
  if (typeof value !== "string") throw new ApiError(400, "research_dataset_payload_invalid", `${field} is required.`);
  const text = value.trim();
  if (text.length < 3 || text.length > max) throw new ApiError(400, "research_dataset_payload_invalid", `${field} is invalid.`);
  return text;
}

function datasetKindCode(value: unknown): ResearchDatasetKind {
  if (typeof value !== "string" || !DATASET_KINDS.has(value as ResearchDatasetKind)) {
    throw new ApiError(400, "research_dataset_kind_invalid", "datasetKind is invalid.");
  }
  return value as ResearchDatasetKind;
}

function purposeCode(value: unknown): string {
  if (typeof value !== "string" || !PURPOSE_CODE.test(value.trim())) {
    throw new ApiError(400, "research_dataset_payload_invalid", "purpose is invalid.");
  }
  return value.trim();
}

function sourceCategoryCode(value: unknown): string {
  if (typeof value !== "string" || !SOURCE_CATEGORY.test(value.trim())) {
    throw new ApiError(400, "research_dataset_payload_invalid", "sourceCategory is invalid.");
  }
  return value.trim();
}

function boundedObject(value: unknown, field: string): Record<string, unknown> {
  if (value == null) return {};
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, "research_dataset_payload_invalid", `${field} must be an object.`);
  }
  const object = value as Record<string, unknown>;
  if (new TextEncoder().encode(JSON.stringify(object)).byteLength > 16_000) {
    throw new ApiError(400, "research_dataset_payload_invalid", `${field} is too large.`);
  }
  return object;
}

function objectPaths(value: Record<string, unknown>, prefix = ""): string[] {
  const result: string[] = [];
  for (const [key, child] of Object.entries(value)) {
    const path = prefix ? `${prefix}.${key}` : key;
    result.push(path);
    if (child && typeof child === "object" && !Array.isArray(child)) {
      result.push(...objectPaths(child as Record<string, unknown>, path));
    }
  }
  return result;
}

function fieldReferences(value: unknown): string[] {
  if (Array.isArray(value)) return value.flatMap(fieldReferences);
  if (!value || typeof value !== "object") return [];
  const result: string[] = [];
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (FIELD_SELECTOR_KEYS.has(key.toLowerCase()) && typeof child === "string") {
      result.push(child.trim());
    }
    result.push(...fieldReferences(child));
  }
  return result;
}

function optionalInteger(value: unknown): number | null {
  if (value == null) return null;
  if (!Number.isInteger(value)) throw new ApiError(400, "research_dataset_payload_invalid", "ageBucketYears must be an integer.");
  return Number(value);
}

function requiredInteger(value: unknown): number {
  if (!Number.isInteger(value)) throw new ApiError(400, "research_dataset_payload_invalid", "Privacy thresholds must be integers.");
  return Number(value);
}

function rowMode(value: unknown): "Aggregate" | "Pseudonymous" {
  if (value !== "Aggregate" && value !== "Pseudonymous") {
    throw new ApiError(400, "research_dataset_payload_invalid", "rowMode is invalid.");
  }
  return value;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
