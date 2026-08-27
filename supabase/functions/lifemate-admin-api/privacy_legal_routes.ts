import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import { createPrivacyLegalAdminStore } from "./privacy_legal_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function createPrivacyLegalAdminRouteHandler(databaseUrl: string) {
  const store = createPrivacyLegalAdminStore(databaseUrl);

  return async function privacyLegalAdminRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    if (request.method === "GET" && path === "/api/v1/privacy/admin") {
      requirePermission(admin, "privacy.admin.read");
      const jurisdiction = requiredJurisdiction(new URL(request.url).searchParams.get("jurisdiction") ?? "GLOBAL");
      const snapshot = await store.snapshot(accountId, jurisdiction);
      return json(snapshot, 200, origin);
    }

    if (request.method === "POST" && path === "/api/v1/privacy/admin/legal-documents") {
      requirePermission(admin, "privacy.admin.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await requiredObject(request);
      const purpose = requiredLegalPurpose(payload.purpose);
      const version = requiredString(payload.version, 1, 64, "legal_document_invalid");
      const jurisdiction = requiredJurisdiction(payload.jurisdiction);
      const title = requiredString(payload.title, 3, 200, "legal_document_invalid");
      const documentHash = requiredString(payload.documentHash, 32, 160, "legal_document_invalid");
      const contentUri = requiredHttpsUrl(payload.contentUri);
      const effectiveAtUtc = requiredTimestamp(payload.effectiveAtUtc);
      const requestHash = await sha256Hex(JSON.stringify({
        purpose,
        version,
        jurisdiction,
        title,
        documentHash,
        contentUri,
        effectiveAtUtc,
      }));
      const result = await store.publish({
        actorAccountId: accountId,
        purpose,
        version,
        jurisdiction,
        title,
        documentHash,
        contentUri,
        effectiveAtUtc,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return mutationResponse(result, origin, "legal_document_publish_failed");
    }

    const retireMatch = path.match(/^\/api\/v1\/privacy\/admin\/legal-documents\/([0-9a-f-]{36})\/retire$/i);
    if (request.method === "POST" && retireMatch) {
      requirePermission(admin, "privacy.admin.write");
      const documentId = requiredUuid(retireMatch[1]);
      const idempotencyKey = requireIdempotencyKey(request);
      const requestHash = await sha256Hex(JSON.stringify({ documentId }));
      const result = await store.retire({
        actorAccountId: accountId,
        documentId,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return mutationResponse(result, origin, "legal_document_retire_failed");
    }

    const purposeMatch = path.match(/^\/api\/v1\/privacy\/admin\/purposes\/([a-z0-9._-]{3,80})$/);
    if (request.method === "PUT" && purposeMatch) {
      requirePermission(admin, "privacy.admin.write");
      const purpose = purposeMatch[1];
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await requiredObject(request);
      const policyVersion = requiredString(payload.policyVersion, 1, 64, "privacy_purpose_invalid");
      const description = requiredString(payload.description, 5, 240, "privacy_purpose_invalid");
      const status = payload.status === "Active" || payload.status === "Retired"
        ? payload.status
        : invalid("privacy_purpose_invalid", "Privacy purpose status is invalid.");
      const requestHash = await sha256Hex(JSON.stringify({ purpose, policyVersion, description, status }));
      const result = await store.updatePurpose({
        actorAccountId: accountId,
        purpose,
        policyVersion,
        description,
        status,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return mutationResponse(result, origin, "privacy_purpose_update_failed");
    }

    return null;
  };
}

async function requiredObject(request: Request): Promise<Record<string, unknown>> {
  const payload = await request.json().catch(() => null);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new ApiError(400, "invalid_json", "Request body is invalid.");
  }
  return payload as Record<string, unknown>;
}

function mutationResponse(result: Record<string, unknown>, origin: string | null, fallback: string): Response {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(503, "privacy_admin_operation_unavailable", "Privacy operation returned an invalid status.");
  }
  if (status >= 400) {
    throw new ApiError(status, String(result.code ?? fallback), "Privacy administration operation failed.");
  }
  return json(result, status, origin);
}

function requiredLegalPurpose(value: unknown): string {
  if (value !== "legal_terms" && value !== "privacy_notice") {
    throw new ApiError(400, "legal_document_invalid", "Legal document purpose is invalid.");
  }
  return value;
}

function requiredJurisdiction(value: unknown): string {
  if (typeof value !== "string") invalid("jurisdiction_invalid", "Jurisdiction is invalid.");
  const result = value.trim().toUpperCase();
  if (!/^[A-Z0-9_-]{2,16}$/.test(result)) invalid("jurisdiction_invalid", "Jurisdiction is invalid.");
  return result;
}

function requiredString(value: unknown, min: number, max: number, code: string): string {
  if (typeof value !== "string") invalid(code, "Value is invalid.");
  const result = value.trim();
  if (result.length < min || result.length > max) invalid(code, "Value is invalid.");
  return result;
}

function requiredHttpsUrl(value: unknown): string {
  if (typeof value !== "string" || value.length > 2048) invalid("legal_document_invalid", "Content URL is invalid.");
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return invalid("legal_document_invalid", "Content URL is invalid.");
  }
  if (url.protocol !== "https:" || url.username || url.password) invalid("legal_document_invalid", "Content URL is invalid.");
  return url.toString();
}

function requiredTimestamp(value: unknown): string {
  if (typeof value !== "string") invalid("legal_document_invalid", "Effective timestamp is invalid.");
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) invalid("legal_document_invalid", "Effective timestamp is invalid.");
  return date.toISOString();
}

function requiredUuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) invalid("invalid_uuid", "Identifier is invalid.");
  return value.toLowerCase();
}

function invalid(code: string, message: string): never {
  throw new ApiError(400, code, message);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((part) => part.toString(16).padStart(2, "0")).join("");
}
