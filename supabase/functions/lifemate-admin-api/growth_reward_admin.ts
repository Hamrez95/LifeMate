import { ApiError, requireUuid } from "./validation.ts";

async function readObject(request: Request): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(declared) && declared > 64 * 1024) {
    throw new ApiError(
      413,
      "growth_reward_request_too_large",
      "Reward request is too large.",
    );
  }
  let value: unknown;
  try {
    value = await request.json();
  } catch {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "Request body must be valid JSON.",
    );
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "Request body must be a JSON object.",
    );
  }
  if (new TextEncoder().encode(JSON.stringify(value)).byteLength > 64 * 1024) {
    throw new ApiError(
      413,
      "growth_reward_request_too_large",
      "Reward request is too large.",
    );
  }
  return value as Record<string, unknown>;
}

function requiredText(
  value: unknown,
  field: string,
  min: number,
  max: number,
): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      `${field} is invalid.`,
    );
  }
  const normalized = value.trim();
  if (normalized.length < min || normalized.length > max) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      `${field} is invalid.`,
    );
  }
  return normalized;
}

function version(value: unknown, field: string, allowZero = false): number {
  const parsed = typeof value === "string" && /^\d+$/.test(value)
    ? Number(value)
    : value;
  if (!Number.isSafeInteger(parsed) || Number(parsed) < (allowZero ? 0 : 1)) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      `${field} is invalid.`,
    );
  }
  return Number(parsed);
}

function optionalLimit(value: unknown): number | null {
  if (value == null) return null;
  const parsed = version(value, "maxIssuesPerAccount");
  if (parsed > 100000) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "maxIssuesPerAccount is invalid.",
    );
  }
  return parsed;
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "rewardConfig must be an object.",
    );
  }
  if (new TextEncoder().encode(JSON.stringify(value)).byteLength > 4096) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "rewardConfig is too large.",
    );
  }
  return value as Record<string, unknown>;
}

export async function parseRewardRuleMutation(request: Request) {
  const body = await readObject(request);
  const triggerKind = requiredText(body.triggerKind, "triggerKind", 4, 24);
  const rewardKind = requiredText(body.rewardKind, "rewardKind", 4, 32);
  const status = requiredText(body.status, "status", 4, 16);
  if (!["Referral", "Advocacy", "Gift", "Campaign"].includes(triggerKind)) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "triggerKind is invalid.",
    );
  }
  if (
    !["Discount", "GiftEntitlement", "RaffleEligibility", "CharityImpact"]
      .includes(rewardKind)
  ) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "rewardKind is invalid.",
    );
  }
  if (!["Draft", "Active", "Paused", "Retired"].includes(status)) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "status is invalid.",
    );
  }
  const code = requiredText(body.code, "code", 3, 80).toLowerCase();
  if (!/^[a-z][a-z0-9._-]{2,79}$/.test(code)) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "code is invalid.",
    );
  }
  return {
    code,
    triggerKind,
    rewardKind,
    rewardConfig: record(body.rewardConfig),
    maxIssuesPerAccount: optionalLimit(body.maxIssuesPerAccount),
    status,
    expectedVersion: body.expectedVersion == null
      ? 0
      : version(body.expectedVersion, "expectedVersion", true),
    reason: requiredText(body.reason, "reason", 10, 1000),
  };
}

export async function parseRewardEventCreate(request: Request) {
  const body = await readObject(request);
  const sourceKind = requiredText(body.sourceKind, "sourceKind", 4, 24);
  if (!["Referral", "Advocacy", "Gift"].includes(sourceKind)) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "sourceKind is invalid.",
    );
  }
  const ruleCode = requiredText(body.ruleCode, "ruleCode", 3, 80).toLowerCase();
  if (!/^[a-z][a-z0-9._-]{2,79}$/.test(ruleCode)) {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "ruleCode is invalid.",
    );
  }
  return {
    beneficiaryAccountId: requireUuid(
      body.beneficiaryAccountId,
      "beneficiaryAccountId",
    ),
    sourceKind,
    sourceId: requireUuid(body.sourceId, "sourceId"),
    ruleCode,
    reason: requiredText(body.reason, "reason", 10, 1000),
  };
}

export async function parseRewardSourceReview(request: Request) {
  const body = await readObject(request);
  const decision = requiredText(body.decision, "decision", 6, 7).toLowerCase();
  if (decision !== "approve" && decision !== "reject") {
    throw new ApiError(
      400,
      "growth_reward_request_invalid",
      "decision is invalid.",
    );
  }
  return {
    expectedVersion: version(body.expectedVersion, "expectedVersion"),
    decision,
    reason: requiredText(body.reason, "reason", 10, 1000),
  };
}

export async function parseRewardFulfillmentRequest(request: Request) {
  const body = await readObject(request);
  return {
    rewardEventId: requireUuid(body.rewardEventId, "rewardEventId"),
    expectedVersion: version(body.expectedVersion, "expectedVersion"),
    reason: requiredText(body.reason, "reason", 10, 1000),
  };
}

export async function parseRewardFulfillmentExecute(request: Request) {
  const body = await readObject(request);
  return {
    rewardEventId: requireUuid(body.rewardEventId, "rewardEventId"),
    expectedVersion: version(body.expectedVersion, "expectedVersion"),
    approvalRequestId: requireUuid(body.approvalRequestId, "approvalRequestId"),
    approvalExpectedVersion: version(
      body.approvalExpectedVersion,
      "approvalExpectedVersion",
    ),
    reason: requiredText(body.reason, "reason", 10, 1000),
  };
}

export function matchRewardSourceReviewPath(
  path: string,
): { sourceKind: "Referral" | "Advocacy"; sourceId: string } | null {
  const match = path.match(
    /^\/api\/v1\/commerce\/rewards\/sources\/(Referral|Advocacy)\/([0-9a-f-]{36})\/review$/i,
  );
  if (!match) return null;
  const sourceKind = match[1].toLowerCase() === "referral"
    ? "Referral"
    : "Advocacy";
  return { sourceKind, sourceId: requireUuid(match[2], "sourceId") };
}

function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{${
    Object.entries(value as Record<string, unknown>).sort(([a], [b]) =>
      a.localeCompare(b)
    ).map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`).join(",")
  }}`;
}

export async function hashGrowthRewardAdminRequest(
  value: unknown,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(stable(value)),
  );
  return [...new Uint8Array(digest)].map((part) =>
    part.toString(16).padStart(2, "0")
  ).join("");
}
