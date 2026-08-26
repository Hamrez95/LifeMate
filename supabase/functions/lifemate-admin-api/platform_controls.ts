import { ApiError } from "./validation.ts";

export type PlatformControlDefinition = {
  key: string;
  kind: "FeatureFlag" | "Config";
  valueType: "Boolean" | "Integer" | "String" | "Json";
  defaultValue: unknown;
  failClosed: boolean;
  version: number;
};

export type PlatformControlRule = {
  id: string;
  priority: number;
  targetType: "Global" | "Product" | "Segment" | "Percentage" | "Beta" | "Account";
  targetKey: string | null;
  rolloutBasisPoints: number | null;
  value: unknown;
  startsAtUtc: string | null;
  endsAtUtc: string | null;
  version: number;
};

export type PlatformControlContext = {
  subjectKey: string;
  productCode?: string | null;
  segmentKeys?: string[];
  beta?: boolean;
  now?: Date;
};

const CONTROL_KEY = /^[a-z][a-z0-9._-]{2,95}$/;

export function parseControlKey(value: string): string {
  const key = value.trim().toLowerCase();
  if (!CONTROL_KEY.test(key)) {
    throw new ApiError(400, "platform_control_key_invalid", "Control key is invalid.");
  }
  return key;
}

function active(rule: PlatformControlRule, now: Date): boolean {
  const start = rule.startsAtUtc ? new Date(rule.startsAtUtc) : null;
  const end = rule.endsAtUtc ? new Date(rule.endsAtUtc) : null;
  return (!start || start <= now) && (!end || end > now);
}

async function bucket(controlKey: string, subjectKey: string): Promise<number> {
  const bytes = new TextEncoder().encode(`${controlKey}:${subjectKey}`);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const value = ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) >>> 0;
  return value % 10000;
}

async function matches(rule: PlatformControlRule, definition: PlatformControlDefinition, context: PlatformControlContext): Promise<boolean> {
  switch (rule.targetType) {
    case "Global": return true;
    case "Product": return !!context.productCode && rule.targetKey === context.productCode;
    case "Segment": return !!rule.targetKey && (context.segmentKeys ?? []).includes(rule.targetKey);
    case "Beta": return context.beta === true && rule.targetKey === "beta";
    case "Account": return !!rule.targetKey && rule.targetKey === context.subjectKey;
    case "Percentage":
      return (await bucket(definition.key, context.subjectKey)) < (rule.rolloutBasisPoints ?? 0);
  }
}

export async function evaluatePlatformControl(
  definition: PlatformControlDefinition,
  rules: PlatformControlRule[],
  context: PlatformControlContext,
) {
  const now = context.now ?? new Date();
  const ordered = [...rules].filter((rule) => active(rule, now)).sort((a, b) => a.priority - b.priority || a.id.localeCompare(b.id));
  for (const rule of ordered) {
    if (await matches(rule, definition, context)) {
      return { value: rule.value, source: "rule" as const, ruleId: rule.id, ruleVersion: rule.version };
    }
  }
  const value = definition.failClosed && definition.kind === "FeatureFlag" && typeof definition.defaultValue !== "boolean"
    ? false
    : definition.defaultValue;
  return { value, source: "default" as const, ruleId: null, ruleVersion: null };
}
