import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  createPrivacyConsentStore,
  type PrivacyDirectoryQuery,
} from "./privacy_consent_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

type DirectoryKind = "document" | "acceptance" | "consent" | "preference";

type JsonObject = Record<string, unknown>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RETIRE_PATH = /^\/api\/v1\/privacy\/documents\/([0-9a-f-]{36})\/retire$/i;
const PUBLISH_PATH = /^\/api\/v1\/privacy\/documents\/([0-9a-f-]{36})\/publish$/i;
const SUMMARY_PATH = /^\/api\/v1\/privacy\/accounts\/([0-9a-f-]{36})\/summary$/i;
const PURPOSE_PATH = /^\/api\/v1\/privacy\/purposes\/([a-z][a-z0-9._-]{2,79})$/;
const REASON = /^[a-z0-9_.-]{3,80}$/;
const JURISDICTION = /^[A-Za-z0-9*_-]{1,16}$/;
const POLICY_VERSION = /^[A-Za-z0-9._-]{1,64}$/;
const DOCUMENT_HASH = /^[A-Za-z0-9:_-]{32,128}$/;

export function createPrivacyConsentRouteHandler(databaseUrl: string) {
  const store = createPrivacyConsentStore(databaseUrl);

  return async function privacyConsentRoute(context: Context): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/privacy/documents") {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(new URL(request.url), "document");
      return json({
        ...(await store.listDocuments(query)),
        filters: { q: query.q, status: query.status },
        lifecycle: {
          draftCreateAllowed: admin.permissions.includes("privacy.consent.manage"),
          draftPublishAllowed: admin.permissions.includes("privacy.consent.manage"),
          draftRetirementAllowed: false,
          activeRetirementAllowed: admin.permissions.includes("privacy.consent.manage"),
          legalAcceptanceAdminRevocationAllowed: false,
        },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "GET" && path === "/api/v1/privacy/acceptances") {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(new URL(request.url), "acceptance");
      return json({
        ...(await store.listAcceptances(query)),
        filters: { q: query.q },
        privacy: {
          accountIdentity: "opaque_uuid_only",
          userAgent: "excluded",
          healthPayload: "excluded",
        },
        lifecycle: { immutableLegalEvidence: true },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "GET" && path === "/api/v1/privacy/consents") {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(new URL(request.url), "consent");
      return json({
        ...(await store.listConsents(query)),
        filters: { q: query.q, status: query.status },
        authority: {
          source: "consent.consent_records",
          healthSharingMutableFromAdmin: false,
        },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "GET" && path === "/api/v1/privacy/preferences") {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(new URL(request.url), "preference");
      return json({
        ...(await store.listPreferences(query)),
        filters: { q: query.q, status: query.status },
        authority: {
          source: "consent.preference_purposes+consent.data_use_consents",
          clinicalConsentIncluded: false,
          adminMayChangeUserChoice: false,
        },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "GET" && path === "/api/v1/privacy/coverage") {
      requirePermission(admin, "privacy.consent.read");
      const jurisdiction = parseJurisdiction(new URL(request.url).searchParams.get("jurisdiction"));
      return json({
        ...(await store.getCoverage(accountId, jurisdiction)),
        privacy: { aggregateOnly: true, rawAccountExport: false },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "GET" && path === "/api/v1/privacy/purposes") {
      requirePermission(admin, "privacy.consent.read");
      return json({
        ...(await store.listPurposeCatalog(accountId)),
        authority: {
          source: "consent.preference_purposes",
          adminMayChangeUserChoice: false,
          mutableFields: ["description", "policyVersion", "status"],
        },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    const summaryMatch = path.match(SUMMARY_PATH);
    if (request.method === "GET" && summaryMatch) {
      requirePermission(admin, "privacy.consent.read");
      const targetAccountId = summaryMatch[1].toLowerCase();
      if (!UUID.test(targetAccountId)) {
        throw new ApiError(400, "privacy_account_id_invalid", "Account identifier is invalid.");
      }
      const jurisdiction = parseJurisdiction(new URL(request.url).searchParams.get("jurisdiction"));
      return json({
        ...(await store.getAccountSummary(accountId, targetAccountId, jurisdiction)),
        privacy: { metadataOnly: true, healthPayload: "excluded", userChoiceMutableFromAdmin: false },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    if (request.method === "POST" && path === "/api/v1/privacy/documents") {
      requirePermission(admin, "privacy.consent.manage");
      const body = await readJsonObject(request);
      rejectUnsupported(body, new Set([
        "purpose", "version", "jurisdiction", "title", "documentHash", "contentUri",
        "effectiveAtUtc", "reasonCode",
      ]));
      const purpose = enumField(body, "purpose", new Set(["legal_terms", "privacy_notice"]));
      const version = boundedString(body, "version", 1, 64, "privacy_version_invalid");
      const jurisdiction = jurisdictionField(body.jurisdiction);
      const title = boundedString(body, "title", 3, 200, "privacy_title_invalid");
      const documentHash = boundedString(body, "documentHash", 32, 128, "privacy_document_hash_invalid");
      if (!DOCUMENT_HASH.test(documentHash)) {
        throw new ApiError(400, "privacy_document_hash_invalid", "documentHash is invalid.");
      }
      const contentUri = boundedString(body, "contentUri", 9, 2048, "privacy_content_uri_invalid");
      if (!isHttpsUrl(contentUri)) {
        throw new ApiError(400, "privacy_content_uri_invalid", "contentUri must use HTTPS.");
      }
      const effectiveAtUtc = optionalTimestamp(body.effectiveAtUtc, "privacy_effective_at_invalid");
      const reasonCode = reasonField(body.reasonCode);
      const idempotencyKey = requireIdempotencyKey(request);
      const requestHash = await sha256({ purpose, version, jurisdiction, title, documentHash, contentUri, effectiveAtUtc, reasonCode });
      const result = await store.createDocument({
        actorAccountId: accountId,
        correlationId,
        idempotencyKey,
        requestHash,
        purpose,
        version,
        jurisdiction,
        title,
        documentHash,
        contentUri,
        effectiveAtUtc,
        reasonCode,
      });
      return json(result, resultStatus(result), origin);
    }

    const publishMatch = path.match(PUBLISH_PATH);
    if (request.method === "POST" && publishMatch) {
      requirePermission(admin, "privacy.consent.manage");
      const documentId = publishMatch[1].toLowerCase();
      if (!UUID.test(documentId)) throw new ApiError(400, "privacy_document_id_invalid", "Document identifier is invalid.");
      const body = await readJsonObject(request);
      rejectUnsupported(body, new Set(["expectedUpdatedAt", "effectiveAtUtc", "reasonCode"]));
      const expectedUpdatedAt = requiredTimestamp(body.expectedUpdatedAt, "privacy_expected_version_invalid");
      const effectiveAtUtc = requiredTimestamp(body.effectiveAtUtc, "privacy_effective_at_invalid");
      const reasonCode = reasonField(body.reasonCode);
      const idempotencyKey = requireIdempotencyKey(request);
      const requestHash = await sha256({ documentId, expectedUpdatedAt, effectiveAtUtc, reasonCode });
      const result = await store.publishDocument({
        actorAccountId: accountId,
        correlationId,
        idempotencyKey,
        requestHash,
        documentId,
        expectedUpdatedAt,
        effectiveAtUtc,
        reasonCode,
      });
      return json(result, resultStatus(result), origin);
    }

    const retireMatch = path.match(RETIRE_PATH);
    if (request.method === "POST" && retireMatch) {
      requirePermission(admin, "privacy.consent.manage");
      const documentId = retireMatch[1].toLowerCase();
      if (!UUID.test(documentId)) {
        throw new ApiError(400, "privacy_document_id_invalid", "Document identifier is invalid.");
      }
      const body = await readJsonObject(request);
      rejectUnsupported(body, new Set(["expectedUpdatedAt", "reasonCode"]));
      const expectedUpdatedAt = requiredTimestamp(body.expectedUpdatedAt, "privacy_expected_version_invalid");
      const reasonCode = reasonField(body.reasonCode);
      const idempotencyKey = requireIdempotencyKey(request);
      const requestHash = await sha256({ documentId, expectedUpdatedAt, reasonCode });
      const result = await store.retireDocument({
        actorAccountId: accountId,
        correlationId,
        idempotencyKey,
        requestHash,
        documentId,
        expectedUpdatedAt,
        reasonCode,
      });
      return json(result, resultStatus(result), origin);
    }

    const purposeMatch = path.match(PURPOSE_PATH);
    if (request.method === "POST" && purposeMatch) {
      requirePermission(admin, "privacy.consent.manage");
      const purpose = purposeMatch[1];
      const body = await readJsonObject(request);
      rejectUnsupported(body, new Set(["expectedUpdatedAt", "description", "policyVersion", "status", "reasonCode"]));
      const expectedUpdatedAt = requiredTimestamp(body.expectedUpdatedAt, "privacy_expected_version_invalid");
      const description = boundedString(body, "description", 3, 240, "privacy_description_invalid");
      const policyVersion = boundedString(body, "policyVersion", 1, 64, "privacy_policy_version_invalid");
      if (!POLICY_VERSION.test(policyVersion)) throw new ApiError(400, "privacy_policy_version_invalid", "policyVersion is invalid.");
      const status = enumField(body, "status", new Set(["Active", "Retired"]));
      const reasonCode = reasonField(body.reasonCode);
      const idempotencyKey = requireIdempotencyKey(request);
      const requestHash = await sha256({ purpose, expectedUpdatedAt, description, policyVersion, status, reasonCode });
      const result = await store.updatePurpose({
        actorAccountId: accountId,
        correlationId,
        idempotencyKey,
        requestHash,
        purpose,
        expectedUpdatedAt,
        description,
        policyVersion,
        status,
        reasonCode,
      });
      return json(result, resultStatus(result), origin);
    }

    return null;
  };
}

export function parseDirectoryQuery(
  url: URL,
  kind: DirectoryKind,
): PrivacyDirectoryQuery {
  const page = positiveInt(url.searchParams.get("page"), 1, 1, 100000);
  const pageSize = positiveInt(url.searchParams.get("pageSize"), 50, 1, 100);
  const q = optionalQuery(url.searchParams.get("q"));
  const status = optionalStatus(url.searchParams.get("status"), kind);
  return { q, status, page, pageSize };
}

function optionalQuery(value: string | null): string | null {
  if (value == null || value.trim() === "") return null;
  const query = value.trim();
  if (query.length > 120) {
    throw new ApiError(400, "privacy_query_invalid", "Search query is too long.");
  }
  return query;
}

function optionalStatus(value: string | null, kind: DirectoryKind): string | null {
  if (value == null || value.trim() === "") return null;
  const normalized = value.trim();
  const allowed = kind === "document"
    ? new Set(["Draft", "Active", "Retired"])
    : kind === "consent"
    ? new Set(["Granted", "Revoked", "Expired", "Superseded"])
    : kind === "preference"
    ? new Set(["Enabled", "Disabled"])
    : new Set<string>();
  if (!allowed.has(normalized)) {
    throw new ApiError(400, "privacy_status_invalid", "Status filter is invalid.");
  }
  return normalized;
}

function positiveInt(raw: string | null, fallback: number, min: number, max: number): number {
  if (raw == null || raw === "") return fallback;
  if (!/^\d+$/.test(raw)) throw new ApiError(400, "privacy_page_invalid", "Pagination value is invalid.");
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    throw new ApiError(400, "privacy_page_invalid", "Pagination value is invalid.");
  }
  return value;
}

async function readJsonObject(request: Request): Promise<JsonObject> {
  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(400, "privacy_payload_invalid", "Request payload must be an object.");
  }
  return body as JsonObject;
}

function rejectUnsupported(body: JsonObject, allowed: Set<string>) {
  if (Object.keys(body).some((key) => !allowed.has(key))) {
    throw new ApiError(400, "privacy_payload_invalid", "Request payload contains unsupported fields.");
  }
}

function boundedString(body: JsonObject, key: string, min: number, max: number, code: string): string {
  const value = typeof body[key] === "string" ? body[key].trim() : "";
  if (value.length < min || value.length > max) throw new ApiError(400, code, `${key} is invalid.`);
  return value;
}

function enumField(body: JsonObject, key: string, allowed: Set<string>): string {
  const value = typeof body[key] === "string" ? body[key].trim() : "";
  if (!allowed.has(value)) throw new ApiError(400, `privacy_${key}_invalid`, `${key} is invalid.`);
  return value;
}

function jurisdictionField(value: unknown): string {
  if (typeof value !== "string" || !JURISDICTION.test(value.trim())) {
    throw new ApiError(400, "privacy_jurisdiction_invalid", "jurisdiction is invalid.");
  }
  return value.trim().toUpperCase();
}

function parseJurisdiction(value: string | null): string {
  if (value == null || value.trim() === "") return "GLOBAL";
  return jurisdictionField(value);
}

function requiredTimestamp(value: unknown, code: string): string {
  if (typeof value !== "string") throw new ApiError(400, code, "Timestamp is required.");
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) throw new ApiError(400, code, "Timestamp is invalid.");
  return date.toISOString();
}

function optionalTimestamp(value: unknown, code: string): string | null {
  if (value === undefined || value === null || value === "") return null;
  return requiredTimestamp(value, code);
}

function reasonField(value: unknown): string {
  if (typeof value !== "string") throw new ApiError(400, "privacy_reason_invalid", "reasonCode is required.");
  const result = value.trim().toLowerCase();
  if (!REASON.test(result)) throw new ApiError(400, "privacy_reason_invalid", "reasonCode is invalid.");
  return result;
}

function isHttpsUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && Boolean(url.hostname);
  } catch {
    return false;
  }
}

async function sha256(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function resultStatus(result: JsonObject): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(503, "privacy_workflow_unavailable", "Privacy workflow returned an invalid status.");
  }
  if (status >= 400) {
    throw new ApiError(status, typeof result.code === "string" ? result.code : "privacy_workflow_failed", "Privacy workflow was not completed.");
  }
  return status;
}
