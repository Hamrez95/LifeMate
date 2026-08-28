import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  createPrivacyConsentStore,
  type PrivacyDirectoryQuery,
} from "./privacy_consent_service.ts";
import { ApiError } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

type DirectoryKind = "document" | "acceptance" | "consent" | "preference";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RETIRE_PATH = /^\/api\/v1\/privacy\/documents\/([0-9a-f-]{36})\/retire$/i;
const REASON = /^[a-z0-9_.-]{3,80}$/;

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
        },
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }

    const retireMatch = path.match(RETIRE_PATH);
    if (request.method === "POST" && retireMatch) {
      requirePermission(admin, "privacy.consent.manage");
      const documentId = retireMatch[1].toLowerCase();
      if (!UUID.test(documentId)) {
        throw new ApiError(400, "privacy_document_id_invalid", "Document identifier is invalid.");
      }
      const body = await request.json().catch(() => null);
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        throw new ApiError(400, "privacy_retire_payload_invalid", "Retirement payload must be an object.");
      }
      const payload = body as Record<string, unknown>;
      const allowed = new Set(["expectedUpdatedAt", "reasonCode"]);
      if (Object.keys(payload).some((key) => !allowed.has(key))) {
        throw new ApiError(400, "privacy_retire_payload_invalid", "Retirement payload contains unsupported fields.");
      }
      const expectedUpdatedAt = requiredTimestamp(payload.expectedUpdatedAt);
      const reasonCode = requiredReason(payload.reasonCode);
      return json(await store.retireDocument({
        actorAccountId: accountId,
        documentId,
        expectedUpdatedAt,
        reasonCode,
        correlationId,
      }), 200, origin);
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

function positiveInt(
  raw: string | null,
  fallback: number,
  min: number,
  max: number,
): number {
  if (raw == null || raw === "") return fallback;
  if (!/^\d+$/.test(raw)) {
    throw new ApiError(400, "privacy_page_invalid", "Pagination value is invalid.");
  }
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    throw new ApiError(400, "privacy_page_invalid", "Pagination value is invalid.");
  }
  return value;
}

function requiredTimestamp(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "privacy_expected_version_invalid", "expectedUpdatedAt is required.");
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new ApiError(400, "privacy_expected_version_invalid", "expectedUpdatedAt is invalid.");
  }
  return date.toISOString();
}

function requiredReason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "privacy_retire_reason_invalid", "reasonCode is required.");
  }
  const result = value.trim().toLowerCase();
  if (!REASON.test(result)) {
    throw new ApiError(400, "privacy_retire_reason_invalid", "reasonCode is invalid.");
  }
  return result;
}
