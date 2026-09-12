import { ApiError } from "./validation.ts";
import type { PlatformControlDefinition } from "./platform_controls.ts";

export type ControlCreate = {
  controlKey: string;
  controlKind: PlatformControlDefinition["kind"];
  valueType: PlatformControlDefinition["valueType"];
  defaultValue: unknown;
  description: string;
  failClosed: boolean;
  reason: string;
};

export type ControlUpdate = {
  expectedVersion: number;
  defaultValue: unknown;
  description: string;
  failClosed: boolean;
  status: "Active" | "Retired";
  reason: string;
};

export type RuleMutation = {
  expectedVersion: number | null;
  priority: number;
  targetType:
    | "Global"
    | "Product"
    | "Segment"
    | "Percentage"
    | "Beta"
    | "Account";
  targetKey: string | null;
  rolloutBasisPoints: number | null;
  value: unknown;
  startsAtUtc: string | null;
  endsAtUtc: string | null;
  status: "Active" | "Disabled" | "Retired";
  reason: string;
};

export type RollbackMutation = {
  expectedVersion: number;
  historyVersion: number;
  reason: string;
};
export type KillSwitchMutation = { expectedVersion: number; reason: string };

const targetKeyPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function objectPayload(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "platform_payload_invalid",
      "Request body must be an object.",
    );
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
  const result = value.trim();
  if (result.length < min || result.length > max) {
    throw new ApiError(400, code, message);
  }
  return result;
}

function reason(value: unknown): string {
  return text(
    value,
    "platform_reason_invalid",
    "reason must be 10 to 1000 characters.",
    10,
    1000,
  );
}

function version(
  value: unknown,
  code = "platform_expected_version_invalid",
): number {
  if (!Number.isSafeInteger(value) || Number(value) < 1) {
    throw new ApiError(400, code, "version must be a positive safe integer.");
  }
  return Number(value);
}

function timestamp(value: unknown, field: string): string | null {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "platform_rule_time_invalid",
      `${field} must be ISO-8601.`,
    );
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new ApiError(
      400,
      "platform_rule_time_invalid",
      `${field} must be ISO-8601.`,
    );
  }
  return parsed.toISOString();
}

export function validateControlValue(
  valueType: PlatformControlDefinition["valueType"],
  value: unknown,
): unknown {
  if (valueType === "Boolean") {
    if (typeof value !== "boolean") {
      throw new ApiError(
        400,
        "platform_value_type_mismatch",
        "Boolean control requires boolean value.",
      );
    }
    return value;
  }
  if (valueType === "Integer") {
    if (!Number.isSafeInteger(value)) {
      throw new ApiError(
        400,
        "platform_value_type_mismatch",
        "Integer control requires safe integer value.",
      );
    }
    return value;
  }
  if (valueType === "String") {
    if (typeof value !== "string" || value.length > 2000) {
      throw new ApiError(
        400,
        "platform_value_type_mismatch",
        "String control requires at most 2000 characters.",
      );
    }
    return value;
  }
  let encoded: string | undefined;
  try {
    encoded = JSON.stringify(value);
  } catch {
    encoded = undefined;
  }
  if (
    encoded === undefined || new TextEncoder().encode(encoded).length > 8192
  ) {
    throw new ApiError(
      400,
      "platform_value_invalid",
      "JSON control value must be at most 8192 bytes.",
    );
  }
  return value;
}

export async function parseControlCreate(
  request: Request,
): Promise<ControlCreate> {
  const body = objectPayload(await request.json());
  const controlKey = text(
    body.controlKey,
    "platform_control_key_invalid",
    "controlKey is invalid.",
    3,
    96,
  ).toLowerCase();
  if (!/^[a-z][a-z0-9._-]{2,95}$/.test(controlKey)) {
    throw new ApiError(
      400,
      "platform_control_key_invalid",
      "controlKey is invalid.",
    );
  }
  if (body.controlKind !== "FeatureFlag" && body.controlKind !== "Config") {
    throw new ApiError(
      400,
      "platform_control_kind_invalid",
      "controlKind is invalid.",
    );
  }
  if (
    !["Boolean", "Integer", "String", "Json"].includes(String(body.valueType))
  ) {
    throw new ApiError(
      400,
      "platform_value_type_invalid",
      "valueType is invalid.",
    );
  }
  const valueType = body.valueType as PlatformControlDefinition["valueType"];
  if (body.controlKind === "FeatureFlag" && valueType !== "Boolean") {
    throw new ApiError(
      400,
      "platform_feature_flag_type_invalid",
      "FeatureFlag controls must be Boolean.",
    );
  }
  if (typeof body.failClosed !== "boolean") {
    throw new ApiError(
      400,
      "platform_fail_closed_invalid",
      "failClosed must be boolean.",
    );
  }
  return {
    controlKey,
    controlKind: body.controlKind,
    valueType,
    defaultValue: validateControlValue(valueType, body.defaultValue),
    description: text(
      body.description,
      "platform_description_invalid",
      "description must be 5 to 240 characters.",
      5,
      240,
    ),
    failClosed: body.failClosed,
    reason: reason(body.reason),
  };
}

export async function parseControlUpdate(
  request: Request,
  valueType: PlatformControlDefinition["valueType"],
): Promise<ControlUpdate> {
  const body = objectPayload(await request.json());
  if (typeof body.failClosed !== "boolean") {
    throw new ApiError(
      400,
      "platform_fail_closed_invalid",
      "failClosed must be boolean.",
    );
  }
  if (body.status !== "Active" && body.status !== "Retired") {
    throw new ApiError(
      400,
      "platform_control_status_invalid",
      "status is invalid.",
    );
  }
  return {
    expectedVersion: version(body.expectedVersion),
    defaultValue: validateControlValue(valueType, body.defaultValue),
    description: text(
      body.description,
      "platform_description_invalid",
      "description must be 5 to 240 characters.",
      5,
      240,
    ),
    failClosed: body.failClosed,
    status: body.status,
    reason: reason(body.reason),
  };
}

export async function parseRuleMutation(
  request: Request,
  valueType: PlatformControlDefinition["valueType"],
  creating: boolean,
): Promise<RuleMutation> {
  const body = objectPayload(await request.json());
  if (
    !["Global", "Product", "Segment", "Percentage", "Beta", "Account"].includes(
      String(body.targetType),
    )
  ) {
    throw new ApiError(
      400,
      "platform_target_type_invalid",
      "targetType is invalid.",
    );
  }
  const targetType = body.targetType as RuleMutation["targetType"];
  let targetKey: string | null = null;
  if (targetType !== "Global") {
    targetKey = text(
      body.targetKey,
      "platform_target_key_invalid",
      "targetKey is invalid.",
      1,
      128,
    );
    if (!targetKeyPattern.test(targetKey)) {
      throw new ApiError(
        400,
        "platform_target_key_invalid",
        "targetKey is invalid.",
      );
    }
  }
  let rolloutBasisPoints: number | null = null;
  if (targetType === "Percentage") {
    if (
      !Number.isInteger(body.rolloutBasisPoints) ||
      Number(body.rolloutBasisPoints) < 0 ||
      Number(body.rolloutBasisPoints) > 10000
    ) {
      throw new ApiError(
        400,
        "platform_rollout_invalid",
        "rolloutBasisPoints must be 0 to 10000.",
      );
    }
    rolloutBasisPoints = Number(body.rolloutBasisPoints);
  } else if (
    body.rolloutBasisPoints !== null && body.rolloutBasisPoints !== undefined
  ) {
    throw new ApiError(
      400,
      "platform_rollout_invalid",
      "rolloutBasisPoints is only valid for Percentage.",
    );
  }
  if (
    !Number.isInteger(body.priority) || Number(body.priority) < 1 ||
    Number(body.priority) > 10000
  ) {
    throw new ApiError(
      400,
      "platform_priority_invalid",
      "priority must be 1 to 10000.",
    );
  }
  if (!["Active", "Disabled", "Retired"].includes(String(body.status))) {
    throw new ApiError(
      400,
      "platform_rule_status_invalid",
      "status is invalid.",
    );
  }
  const startsAtUtc = timestamp(body.startsAtUtc, "startsAtUtc");
  const endsAtUtc = timestamp(body.endsAtUtc, "endsAtUtc");
  if (
    startsAtUtc && endsAtUtc && new Date(endsAtUtc) <= new Date(startsAtUtc)
  ) {
    throw new ApiError(
      400,
      "platform_rule_window_invalid",
      "endsAtUtc must be after startsAtUtc.",
    );
  }
  return {
    expectedVersion: creating ? null : version(body.expectedVersion),
    priority: Number(body.priority),
    targetType,
    targetKey,
    rolloutBasisPoints,
    value: validateControlValue(valueType, body.value),
    startsAtUtc,
    endsAtUtc,
    status: body.status as RuleMutation["status"],
    reason: reason(body.reason),
  };
}

export async function parseRollbackMutation(
  request: Request,
): Promise<RollbackMutation> {
  const body = objectPayload(await request.json());
  return {
    expectedVersion: version(body.expectedVersion),
    historyVersion: version(
      body.historyVersion,
      "platform_history_version_invalid",
    ),
    reason: reason(body.reason),
  };
}

export async function parseKillSwitchMutation(
  request: Request,
): Promise<KillSwitchMutation> {
  const body = objectPayload(await request.json());
  return {
    expectedVersion: version(body.expectedVersion),
    reason: reason(body.reason),
  };
}

export function matchRuleId(path: string): string | null {
  const match = path.match(/^\/api\/v1\/platform\/control-rules\/([^/]+)$/);
  if (!match) return null;
  if (!uuidPattern.test(match[1])) {
    throw new ApiError(400, "platform_rule_id_invalid", "rule id is invalid.");
  }
  return match[1];
}

export async function platformRequestHash(
  operation: string,
  payload: unknown,
): Promise<string> {
  const bytes = new TextEncoder().encode(
    JSON.stringify({ operation, payload }),
  );
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}
