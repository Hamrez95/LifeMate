import { ApiError, requireUuid } from "./validation.ts";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function body(request: Request): Promise<Record<string, unknown>> {
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "growth_reward_request_invalid", "Request body must be a JSON object.");
  }
}

function text(value: unknown, field: string, min: number, max: number): string {
  if (typeof value !== "string") throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  const result = value.trim();
  if (result.length < min || result.length > max) throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  return result;
}

function positiveInteger(value: unknown, field: string, nullable = false): number | null {
  if (nullable && value == null) return null;
  const parsed = typeof value === "string" && /^\d+$/.test(value) ? Number(value) : value;
  if (!Number.isSafeInteger(parsed) || Number(parsed) < 1) throw new ApiError(400, `${field}_invalid`, `${field} must be a positive integer.`);
  return Number(parsed);
}

function optionalUuid(value: unknown, field: string): string | null {
  if (value == null) return null;
  const normalized = String(value).trim().toLowerCase();
  if (!uuidPattern.test(normalized)) throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  return normalized;
}

function object(value: unknown, field: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new ApiError(400, `${field}_invalid`, `${field} must be an object.`);
  return value as Record<string, unknown>;
}

export type RewardIssuePayload = {
  beneficiaryAccountId: string;
  sourceKind: "Referral" | "Advocacy" | "Gift" | "Campaign";
  sourceId: string;
  rewardRuleId: string;
  expectedRuleVersion: number;
  provenanceHash: string;
  reason: string;
};

function issueFields(value: Record<string, unknown>): RewardIssuePayload {
  const sourceKind = text(value.sourceKind, "source_kind", 4, 24);
  if (!["Referral", "Advocacy", "Gift", "Campaign"].includes(sourceKind)) {
    throw new ApiError(400, "source_kind_invalid", "sourceKind is invalid.");
  }
  const provenanceHash = text(value.provenanceHash, "provenance_hash", 64, 128).toLowerCase();
  if (!/^[0-9a-f]{64,128}$/.test(provenanceHash)) throw new ApiError(400, "provenance_hash_invalid", "provenanceHash is invalid.");
  return {
    beneficiaryAccountId: requireUuid(String(value.beneficiaryAccountId ?? ""), "beneficiaryAccountId"),
    sourceKind: sourceKind as RewardIssuePayload["sourceKind"],
    sourceId: requireUuid(String(value.sourceId ?? ""), "sourceId"),
    rewardRuleId: requireUuid(String(value.rewardRuleId ?? ""), "rewardRuleId"),
    expectedRuleVersion: positiveInteger(value.expectedRuleVersion, "expected_rule_version")!,
    provenanceHash,
    reason: text(value.reason, "reason", 10, 1000),
  };
}

export async function parseRewardRuleUpsert(request: Request) {
  const value = await body(request);
  const triggerKind = text(value.triggerKind, "trigger_kind", 4, 24);
  const rewardKind = text(value.rewardKind, "reward_kind", 4, 32);
  const status = text(value.status, "status", 4, 16);
  if (!["Referral", "Advocacy", "Gift", "Campaign"].includes(triggerKind)) throw new ApiError(400, "trigger_kind_invalid", "triggerKind is invalid.");
  if (!["Discount", "GiftEntitlement", "RaffleEligibility", "CharityImpact"].includes(rewardKind)) throw new ApiError(400, "reward_kind_invalid", "rewardKind is invalid.");
  if (!["Draft", "Active", "Paused", "Retired"].includes(status)) throw new ApiError(400, "reward_status_invalid", "status is invalid.");
  return {
    id: optionalUuid(value.id, "id"),
    code: text(value.code, "code", 3, 80).toLowerCase(),
    triggerKind,
    rewardKind,
    rewardConfig: object(value.rewardConfig, "reward_config"),
    maxIssuesPerAccount: positiveInteger(value.maxIssuesPerAccount, "max_issues_per_account", true),
    status,
    expectedVersion: positiveInteger(value.expectedVersion, "expected_version", true),
    reason: text(value.reason, "reason", 10, 1000),
  };
}

export async function parseAdvocacyReview(request: Request) {
  const value = await body(request);
  const decision = text(value.decision, "decision", 6, 8).toLowerCase();
  if (decision !== "verify" && decision !== "reject") throw new ApiError(400, "advocacy_decision_invalid", "decision must be verify or reject.");
  return {
    expectedVersion: positiveInteger(value.expectedVersion, "expected_version")!,
    decision,
    reason: text(value.reason, "reason", 10, 1000),
  };
}

export async function parseRewardIssueRequest(request: Request): Promise<RewardIssuePayload> {
  return issueFields(await body(request));
}

export async function parseRewardIssueExecute(request: Request) {
  const value = await body(request);
  return {
    ...issueFields(value),
    approvalRequestId: requireUuid(String(value.approvalRequestId ?? ""), "approvalRequestId"),
    approvalExpectedVersion: positiveInteger(value.approvalExpectedVersion, "approval_expected_version")!,
  };
}

function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{${Object.entries(value as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${JSON.stringify(k)}:${stable(v)}`).join(",")}}`;
}

export async function hashGrowthRewardRequest(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(stable(value)));
  return [...new Uint8Array(digest)].map((part) => part.toString(16).padStart(2, "0")).join("");
}

export function matchAdvocacyReviewPath(path: string): string | null {
  return path.match(/^\/api\/v1\/commerce\/rewards\/advocacy\/([0-9a-f-]{36})\/review$/i)?.[1] ?? null;
}
