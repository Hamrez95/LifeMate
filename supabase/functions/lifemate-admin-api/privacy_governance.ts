import { ApiError } from "./validation.ts";

export type LegalDocumentCreate = {
  purpose: "legal_terms" | "privacy_notice";
  version: string;
  jurisdiction: string;
  title: string;
  documentHash: string;
  contentUri: string;
  effectiveAtUtc: string;
  reason: string;
};

export type LegalDocumentStatusMutation = {
  reason: string;
};

export type PreferencePurposeMutation = {
  description: string;
  policyVersion: string;
  status: "Active" | "Retired";
  reason: string;
};

const versionPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const jurisdictionPattern = /^[A-Z][A-Z0-9._-]{1,31}$/;
const purposePattern = /^[a-z][a-z0-9._-]{2,79}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const hashPattern = /^[A-Fa-f0-9]{32,160}$/;

function objectPayload(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, "privacy_payload_invalid", "Request body must be an object.");
  }
  return value as Record<string, unknown>;
}

function text(
  value: unknown,
  code: string,
  message: string,
  min: number,
  max: number,
): string {
  if (typeof value !== "string") throw new ApiError(400, code, message);
  const normalized = value.trim();
  if (normalized.length < min || normalized.length > max) {
    throw new ApiError(400, code, message);
  }
  return normalized;
}

function reason(value: unknown): string {
  return text(value, "privacy_reason_invalid", "reason must be 10 to 1000 characters.", 10, 1000);
}

function isoTimestamp(value: unknown): string {
  const raw = text(value, "legal_effective_at_invalid", "effectiveAtUtc must be an ISO-8601 timestamp.", 10, 64);
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw new ApiError(400, "legal_effective_at_invalid", "effectiveAtUtc must be an ISO-8601 timestamp.");
  }
  return parsed.toISOString();
}

export async function parseLegalDocumentCreate(request: Request): Promise<LegalDocumentCreate> {
  const body = objectPayload(await request.json());
  const purpose = body.purpose;
  if (purpose !== "legal_terms" && purpose !== "privacy_notice") {
    throw new ApiError(400, "legal_purpose_invalid", "purpose must be legal_terms or privacy_notice.");
  }
  const version = text(body.version, "legal_version_invalid", "version is invalid.", 1, 64);
  if (!versionPattern.test(version)) throw new ApiError(400, "legal_version_invalid", "version is invalid.");
  const jurisdiction = text(body.jurisdiction, "legal_jurisdiction_invalid", "jurisdiction is invalid.", 2, 32).toUpperCase();
  if (!jurisdictionPattern.test(jurisdiction)) throw new ApiError(400, "legal_jurisdiction_invalid", "jurisdiction is invalid.");
  const documentHash = text(body.documentHash, "legal_document_hash_invalid", "documentHash is invalid.", 32, 160);
  if (!hashPattern.test(documentHash)) throw new ApiError(400, "legal_document_hash_invalid", "documentHash is invalid.");
  const contentUri = text(body.contentUri, "legal_content_uri_invalid", "contentUri must be an HTTPS URL.", 9, 1000);
  let uri: URL;
  try { uri = new URL(contentUri); } catch { throw new ApiError(400, "legal_content_uri_invalid", "contentUri must be an HTTPS URL."); }
  if (uri.protocol !== "https:") throw new ApiError(400, "legal_content_uri_invalid", "contentUri must be an HTTPS URL.");
  return {
    purpose,
    version,
    jurisdiction,
    title: text(body.title, "legal_title_invalid", "title must be 2 to 200 characters.", 2, 200),
    documentHash,
    contentUri: uri.toString(),
    effectiveAtUtc: isoTimestamp(body.effectiveAtUtc),
    reason: reason(body.reason),
  };
}

export async function parseLegalDocumentStatusMutation(request: Request): Promise<LegalDocumentStatusMutation> {
  const body = objectPayload(await request.json());
  return { reason: reason(body.reason) };
}

export async function parsePreferencePurposeMutation(request: Request): Promise<PreferencePurposeMutation> {
  const body = objectPayload(await request.json());
  const policyVersion = text(body.policyVersion, "privacy_policy_version_invalid", "policyVersion is invalid.", 1, 64);
  if (!versionPattern.test(policyVersion)) throw new ApiError(400, "privacy_policy_version_invalid", "policyVersion is invalid.");
  if (body.status !== "Active" && body.status !== "Retired") {
    throw new ApiError(400, "privacy_purpose_status_invalid", "status must be Active or Retired.");
  }
  return {
    description: text(body.description, "privacy_purpose_description_invalid", "description must be 5 to 240 characters.", 5, 240),
    policyVersion,
    status: body.status,
    reason: reason(body.reason),
  };
}

export function matchLegalDocumentActionPath(path: string): { id: string; action: "publish" | "retire" } | null {
  const match = path.match(/^\/api\/v1\/privacy\/governance\/documents\/([^/]+)\/(publish|retire)$/);
  if (!match) return null;
  const id = match[1];
  if (!uuidPattern.test(id)) throw new ApiError(400, "legal_document_id_invalid", "Document id is invalid.");
  return { id, action: match[2] as "publish" | "retire" };
}

export function matchPreferencePurposePath(path: string): string | null {
  const match = path.match(/^\/api\/v1\/privacy\/governance\/purposes\/([^/]+)$/);
  if (!match) return null;
  const purpose = decodeURIComponent(match[1]).toLowerCase();
  if (!purposePattern.test(purpose)) throw new ApiError(400, "privacy_purpose_invalid", "Purpose is invalid.");
  return purpose;
}

export async function requestHash(operation: string, payload: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify({ operation, payload }));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
