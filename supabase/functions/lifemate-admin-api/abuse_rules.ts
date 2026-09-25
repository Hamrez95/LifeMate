import { ApiError } from "./validation.ts";

export type AbuseRuleMutation = {
  code: string;
  contextCode: string;
  displayName: string;
  ruleKind:
    | "VelocityLimit"
    | "UsageCap"
    | "Cooldown"
    | "DuplicateKey"
    | "EvidenceRequired";
  subjectScope: "Account" | "VerifiedPhone";
  enforcementAction: "Allow" | "Deny" | "RequireApproval";
  windowSeconds: number | null;
  maxCount: number | null;
  cooldownSeconds: number | null;
  evidenceCode: string | null;
  approvalRequestType: string | null;
  priority: number;
  expectedVersion: number | null;
  reason: string;
};

export type AbuseRuleRetire = { expectedVersion: number; reason: string };

const keyPattern = /^[a-z][a-z0-9._-]{2,79}$/;
const kinds = new Set([
  "VelocityLimit",
  "UsageCap",
  "Cooldown",
  "DuplicateKey",
  "EvidenceRequired",
]);
const scopes = new Set(["Account", "VerifiedPhone"]);
const actions = new Set(["Allow", "Deny", "RequireApproval"]);

async function objectBody(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(400, "json_invalid", "Request body must be valid JSON.");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(
      400,
      "body_invalid",
      "Request body must be a JSON object.",
    );
  }
  return body as Record<string, unknown>;
}

function text(
  value: unknown,
  field: string,
  min: number,
  max: number,
): string {
  if (typeof value !== "string") {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  const result = value.trim();
  if (result.length < min || result.length > max) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return result;
}

function key(
  value: unknown,
  field: string,
  nullable = false,
): string | null {
  if (
    nullable &&
    (value === null || value === undefined || value === "")
  ) return null;
  const result = text(value, field, 3, 80).toLowerCase();
  if (!keyPattern.test(result)) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return result;
}

function integer(
  value: unknown,
  field: string,
  min: number,
  max: number,
  nullable = false,
): number | null {
  if (nullable && (value === null || value === undefined)) return null;
  if (
    !Number.isInteger(value) ||
    Number(value) < min ||
    Number(value) > max
  ) {
    throw new ApiError(
      400,
      `${field}_invalid`,
      `${field} is outside the allowed range.`,
    );
  }
  return Number(value);
}

export async function parseAbuseRuleMutation(
  request: Request,
): Promise<AbuseRuleMutation> {
  const body = await objectBody(request);
  const code = key(body.code, "code")!;
  const contextCode = key(body.contextCode, "context_code")!;
  const displayName = text(body.displayName, "display_name", 2, 160);
  const ruleKind = text(body.ruleKind, "rule_kind", 4, 32);
  const subjectScope = text(body.subjectScope, "subject_scope", 4, 24);
  const enforcementAction = text(
    body.enforcementAction,
    "enforcement_action",
    4,
    24,
  );
  if (!kinds.has(ruleKind)) {
    throw new ApiError(400, "rule_kind_invalid", "ruleKind is invalid.");
  }
  if (!scopes.has(subjectScope)) {
    throw new ApiError(
      400,
      "subject_scope_invalid",
      "subjectScope is invalid.",
    );
  }
  if (!actions.has(enforcementAction)) {
    throw new ApiError(
      400,
      "enforcement_action_invalid",
      "enforcementAction is invalid.",
    );
  }

  const windowSeconds = integer(
    body.windowSeconds,
    "window_seconds",
    1,
    31536000,
    true,
  );
  const maxCount = integer(body.maxCount, "max_count", 1, 1000000, true);
  const cooldownSeconds = integer(
    body.cooldownSeconds,
    "cooldown_seconds",
    1,
    31536000,
    true,
  );
  const evidenceCode = key(body.evidenceCode, "evidence_code", true);
  const approvalRequestType = key(
    body.approvalRequestType,
    "approval_request_type",
    true,
  );
  const priority = integer(body.priority ?? 100, "priority", 1, 10000)!;
  const expectedVersion = integer(
    body.expectedVersion,
    "expected_version",
    1,
    Number.MAX_SAFE_INTEGER,
    true,
  );
  const reason = text(body.reason, "reason", 10, 1000);

  if (
    enforcementAction === "RequireApproval"
      ? !approvalRequestType
      : approvalRequestType !== null
  ) {
    throw new ApiError(
      400,
      "approval_request_type_invalid",
      "RequireApproval must name exactly one approvalRequestType.",
    );
  }
  const shapeValid = (ruleKind === "VelocityLimit" &&
    windowSeconds !== null &&
    maxCount !== null &&
    cooldownSeconds === null &&
    evidenceCode === null) ||
    (ruleKind === "UsageCap" &&
      windowSeconds === null &&
      maxCount !== null &&
      cooldownSeconds === null &&
      evidenceCode === null) ||
    (ruleKind === "Cooldown" &&
      windowSeconds === null &&
      maxCount === null &&
      cooldownSeconds !== null &&
      evidenceCode === null) ||
    (ruleKind === "DuplicateKey" &&
      windowSeconds === null &&
      maxCount === null &&
      cooldownSeconds === null &&
      evidenceCode === null) ||
    (ruleKind === "EvidenceRequired" &&
      windowSeconds === null &&
      maxCount === null &&
      cooldownSeconds === null &&
      evidenceCode !== null);
  if (!shapeValid) {
    throw new ApiError(
      400,
      "abuse_rule_shape_invalid",
      "Rule parameters do not match ruleKind.",
    );
  }

  return {
    code,
    contextCode,
    displayName,
    ruleKind: ruleKind as AbuseRuleMutation["ruleKind"],
    subjectScope: subjectScope as AbuseRuleMutation["subjectScope"],
    enforcementAction:
      enforcementAction as AbuseRuleMutation["enforcementAction"],
    windowSeconds,
    maxCount,
    cooldownSeconds,
    evidenceCode,
    approvalRequestType,
    priority,
    expectedVersion,
    reason,
  };
}

export async function parseAbuseRuleRetire(
  request: Request,
): Promise<AbuseRuleRetire> {
  const body = await objectBody(request);
  return {
    expectedVersion: integer(
      body.expectedVersion,
      "expected_version",
      1,
      Number.MAX_SAFE_INTEGER,
    )!,
    reason: text(body.reason, "reason", 10, 1000),
  };
}

export function matchAbuseRuleRetirePath(path: string): string | null {
  const match = path.match(
    /^\/api\/v1\/security\/abuse\/rules\/([0-9a-f-]{36})\/actions\/retire$/i,
  );
  return match?.[1] ?? null;
}

export function matchAbuseRuleVersionsPath(path: string): string | null {
  const match = path.match(
    /^\/api\/v1\/security\/abuse\/rules\/([0-9a-f-]{36})\/versions$/i,
  );
  return match?.[1] ?? null;
}

function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{$${
    Object.entries(value as Record<string, unknown>)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([k, v]) => `${JSON.stringify(k)}:${stable(v)}`)
      .join(",")
  }}`.replace("{$", "{");
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function hashAbuseRuleMutation(
  payload: AbuseRuleMutation,
): Promise<string> {
  return sha256(stable(payload));
}

export async function hashAbuseRuleRetire(
  id: string,
  payload: AbuseRuleRetire,
): Promise<string> {
  return sha256(stable({ id, ...payload }));
}
