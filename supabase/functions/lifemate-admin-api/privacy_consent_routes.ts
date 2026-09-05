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
type DirectoryKind =
  | "document"
  | "acceptance"
  | "consent"
  | "preference"
  | "preference-policy";
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DOCUMENT_ACTION =
  /^\/api\/v1\/privacy\/documents\/([0-9a-f-]{36})\/(publish|retire)$/i;
const USER_SUMMARY = /^\/api\/v1\/privacy\/users\/([0-9a-f-]{36})\/summary$/i;
const PREFERENCE =
  /^\/api\/v1\/privacy\/preference-purposes\/([a-z][a-z0-9._-]{2,79})$/;
const REASON = /^[a-z0-9_.-]{3,80}$/;

export function createPrivacyConsentRouteHandler(databaseUrl: string) {
  const store = createPrivacyConsentStore(databaseUrl);
  return async function route(context: Context): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;
    if (request.method === "GET" && path === "/api/v1/privacy/documents") {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(new URL(request.url), "document");
      return json(
        {
          ...await store.listDocuments(query),
          filters: { q: query.q, status: query.status },
          lifecycle: {
            draftPublishAllowed: admin.permissions.includes(
              "privacy.consent.manage",
            ),
            activeRetirementAllowed: admin.permissions.includes(
              "privacy.consent.manage",
            ),
            legalAcceptanceAdminRevocationAllowed: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }
    if (request.method === "GET" && path === "/api/v1/privacy/acceptances") {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(new URL(request.url), "acceptance");
      return json(
        {
          ...await store.listAcceptances(query),
          filters: { q: query.q },
          privacy: {
            accountIdentity: "opaque_uuid_only",
            userAgent: "excluded",
            healthPayload: "excluded",
          },
          lifecycle: { immutableLegalEvidence: true },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }
    if (request.method === "GET" && path === "/api/v1/privacy/consents") {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(new URL(request.url), "consent");
      return json(
        {
          ...await store.listConsents(query),
          filters: { q: query.q, status: query.status },
          authority: {
            source: "consent.consent_records",
            healthSharingMutableFromAdmin: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }
    if (request.method === "GET" && path === "/api/v1/privacy/preferences") {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(new URL(request.url), "preference");
      return json(
        {
          ...await store.listPreferences(query),
          filters: { q: query.q, status: query.status },
          authority: {
            source: "consent.preference_purposes+consent.data_use_consents",
            accountPreferenceMutableFromAdmin: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }
    if (
      request.method === "GET" && path === "/api/v1/privacy/preference-purposes"
    ) {
      requirePermission(admin, "privacy.consent.read");
      const query = parseDirectoryQuery(
        new URL(request.url),
        "preference-policy",
      );
      return json(
        {
          ...await store.listPreferencePurposePolicies(query),
          filters: { q: query.q, status: query.status },
          authority: {
            source: "consent.preference_purposes",
            policyMutableWith: "privacy.consent.manage",
            accountPreferenceMutableFromAdmin: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }
    if (request.method === "GET" && path === "/api/v1/privacy/coverage") {
      requirePermission(admin, "privacy.consent.read");
      const jurisdiction =
        (new URL(request.url).searchParams.get("jurisdiction") || "GLOBAL")
          .toUpperCase();
      if (!/^[A-Z0-9*-]{1,16}$/.test(jurisdiction)) {
        throw new ApiError(
          400,
          "privacy_jurisdiction_invalid",
          "Jurisdiction is invalid.",
        );
      }
      return json(await store.coverage(accountId, jurisdiction), 200, origin);
    }
    const summary = path.match(USER_SUMMARY);
    if (request.method === "GET" && summary) {
      requirePermission(admin, "privacy.consent.read");
      if (!UUID.test(summary[1])) {
        throw new ApiError(
          400,
          "privacy_account_id_invalid",
          "Account identifier is invalid.",
        );
      }
      return json(
        await store.userSummary(accountId, summary[1].toLowerCase()),
        200,
        origin,
      );
    }
    if (request.method === "POST" && path === "/api/v1/privacy/documents") {
      requirePermission(admin, "privacy.consent.manage");
      const idempotencyKey = requireIdempotencyKey(request);
      const p = await objectBody(request);
      exactKeys(p, [
        "purpose",
        "version",
        "jurisdiction",
        "title",
        "documentHash",
        "contentUri",
        "effectiveAtUtc",
        "reasonCode",
      ]);
      const input = {
        actorAccountId: accountId,
        purpose: text(p.purpose),
        version: text(p.version),
        jurisdiction: text(p.jurisdiction),
        title: text(p.title),
        documentHash: text(p.documentHash),
        contentUri: text(p.contentUri),
        effectiveAtUtc: requiredTimestamp(p.effectiveAtUtc),
        reason: requiredReason(p.reasonCode),
        correlationId,
        idempotencyKey,
      };
      const r = await store.createDocument({
        ...input,
        requestHash: await hash(input),
      });
      return mutation(r, origin);
    }
    const action = path.match(DOCUMENT_ACTION);
    if (request.method === "POST" && action) {
      requirePermission(admin, "privacy.consent.manage");
      const idempotencyKey = requireIdempotencyKey(request);
      const p = await objectBody(request);
      exactKeys(p, ["expectedUpdatedAt", "reasonCode"]);
      const input = {
        actorAccountId: accountId,
        documentId: action[1].toLowerCase(),
        expectedUpdatedAt: requiredTimestamp(p.expectedUpdatedAt),
        reason: requiredReason(p.reasonCode),
        correlationId,
        idempotencyKey,
      };
      const r = action[2].toLowerCase() === "publish"
        ? await store.publishDocument({
          ...input,
          requestHash: await hash(input),
        })
        : await store.retireDocument({
          ...input,
          requestHash: await hash(input),
        });
      return mutation(r, origin);
    }
    const preference = path.match(PREFERENCE);
    if (request.method === "PUT" && preference) {
      requirePermission(admin, "privacy.consent.manage");
      const idempotencyKey = requireIdempotencyKey(request);
      const p = await objectBody(request);
      exactKeys(p, [
        "expectedUpdatedAt",
        "description",
        "policyVersion",
        "status",
        "reasonCode",
      ]);
      const input = {
        actorAccountId: accountId,
        purpose: preference[1],
        expectedUpdatedAt: requiredTimestamp(p.expectedUpdatedAt),
        description: text(p.description),
        policyVersion: text(p.policyVersion),
        status: text(p.status),
        reason: requiredReason(p.reasonCode),
        correlationId,
        idempotencyKey,
      };
      const r = await store.updatePreference({
        ...input,
        requestHash: await hash(input),
      });
      return mutation(r, origin);
    }
    return null;
  };
}

function mutation(r: Record<string, unknown>, origin: string | null) {
  const status = Number(r.httpStatus ?? 200);
  if (status >= 400) {
    throw new ApiError(
      status,
      typeof r.code === "string" ? r.code : "privacy_mutation_failed",
      "Privacy mutation was not completed.",
    );
  }
  return json(r, status, origin);
}
async function objectBody(request: Request) {
  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(
      400,
      "privacy_payload_invalid",
      "Payload must be an object.",
    );
  }
  return body as Record<string, unknown>;
}
function exactKeys(p: Record<string, unknown>, allowed: string[]) {
  const set = new Set(allowed);
  if (Object.keys(p).some((k) => !set.has(k))) {
    throw new ApiError(
      400,
      "privacy_payload_invalid",
      "Payload contains unsupported fields.",
    );
  }
}
function text(v: unknown) {
  if (typeof v !== "string" || !v.trim()) {
    throw new ApiError(
      400,
      "privacy_payload_invalid",
      "Required text is missing.",
    );
  }
  return v.trim();
}
async function hash(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  ).map((b) => b.toString(16).padStart(2, "0")).join("");
}
export function parseDirectoryQuery(
  url: URL,
  kind: DirectoryKind,
): PrivacyDirectoryQuery {
  return {
    page: positiveInt(url.searchParams.get("page"), 1, 1, 100000),
    pageSize: positiveInt(url.searchParams.get("pageSize"), 50, 1, 100),
    q: optionalQuery(url.searchParams.get("q")),
    status: optionalStatus(url.searchParams.get("status"), kind),
  };
}
function optionalQuery(v: string | null) {
  if (v == null || v.trim() === "") return null;
  const q = v.trim();
  if (q.length > 120) {
    throw new ApiError(
      400,
      "privacy_query_invalid",
      "Search query is too long.",
    );
  }
  return q;
}
function optionalStatus(v: string | null, kind: DirectoryKind) {
  if (v == null || v.trim() === "") return null;
  const n = v.trim();
  const allowed = kind === "document"
    ? new Set(["Draft", "Active", "Retired"])
    : kind === "consent"
    ? new Set(["Granted", "Revoked", "Expired", "Superseded"])
    : kind === "preference"
    ? new Set(["Enabled", "Disabled"])
    : kind === "preference-policy"
    ? new Set(["Active", "Retired"])
    : new Set<string>();
  if (!allowed.has(n)) {
    throw new ApiError(
      400,
      "privacy_status_invalid",
      "Status filter is invalid.",
    );
  }
  return n;
}
function positiveInt(
  raw: string | null,
  fallback: number,
  min: number,
  max: number,
) {
  if (raw == null || raw === "") return fallback;
  if (!/^\d+$/.test(raw)) {
    throw new ApiError(
      400,
      "privacy_page_invalid",
      "Pagination value is invalid.",
    );
  }
  const v = Number(raw);
  if (!Number.isSafeInteger(v) || v < min || v > max) {
    throw new ApiError(
      400,
      "privacy_page_invalid",
      "Pagination value is invalid.",
    );
  }
  return v;
}
function requiredTimestamp(v: unknown) {
  if (typeof v !== "string") {
    throw new ApiError(
      400,
      "privacy_expected_version_invalid",
      "Timestamp is required.",
    );
  }
  const d = new Date(v);
  if (!Number.isFinite(d.getTime())) {
    throw new ApiError(
      400,
      "privacy_expected_version_invalid",
      "Timestamp is invalid.",
    );
  }
  return d.toISOString();
}
function requiredReason(v: unknown) {
  if (typeof v !== "string") {
    throw new ApiError(
      400,
      "privacy_reason_invalid",
      "reasonCode is required.",
    );
  }
  const r = v.trim().toLowerCase();
  if (!REASON.test(r)) {
    throw new ApiError(400, "privacy_reason_invalid", "reasonCode is invalid.");
  }
  return r;
}
