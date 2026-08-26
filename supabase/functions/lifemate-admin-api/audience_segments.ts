import { ApiError } from "./validation.ts";

export type SegmentOperator =
  | "eq"
  | "neq"
  | "in"
  | "not_in"
  | "gte"
  | "lte"
  | "exists";

export type SegmentAttribute =
  | "demographic.age_bucket"
  | "demographic.locale"
  | "product.code"
  | "product.enrolled"
  | "subscription.status"
  | "entitlement.code"
  | "engagement.lifecycle"
  | "engagement.last_active_days"
  | "campaign.channel"
  | "campaign.last_outcome";

export type SegmentRule = {
  attribute: SegmentAttribute;
  operator: SegmentOperator;
  value?: string | number | boolean | Array<string | number | boolean>;
};

export type SegmentRuleSet = {
  version: 1;
  match: "all" | "any";
  rules: SegmentRule[];
};

const ALLOWED_ATTRIBUTES = new Set<SegmentAttribute>([
  "demographic.age_bucket",
  "demographic.locale",
  "product.code",
  "product.enrolled",
  "subscription.status",
  "entitlement.code",
  "engagement.lifecycle",
  "engagement.last_active_days",
  "campaign.channel",
  "campaign.last_outcome",
]);

const FORBIDDEN_ATTRIBUTE_PREFIXES = [
  "health.",
  "medication.",
  "diagnosis.",
  "treatment.",
  "women_health.",
  "cycle.",
] as const;

const OPERATORS = new Set<SegmentOperator>([
  "eq",
  "neq",
  "in",
  "not_in",
  "gte",
  "lte",
  "exists",
]);

function invalid(message: string): never {
  throw new ApiError(400, "segment_rule_invalid", message);
}

function isScalar(value: unknown): value is string | number | boolean {
  return typeof value === "string" || typeof value === "number" ||
    typeof value === "boolean";
}

function validateValue(operator: SegmentOperator, value: unknown): SegmentRule["value"] {
  if (operator === "exists") {
    if (value !== undefined) invalid("exists rules must not include a value.");
    return undefined;
  }

  if (value === undefined || value === null) {
    invalid("Segment rule value is required.");
  }

  if (operator === "in" || operator === "not_in") {
    if (!Array.isArray(value) || value.length === 0 || value.length > 50) {
      invalid("Set operators require between 1 and 50 scalar values.");
    }
    if (!value.every(isScalar)) invalid("Segment set values must be scalar.");
    return [...value];
  }

  if (!isScalar(value)) invalid("Segment rule value must be scalar.");
  return value;
}

export function parseSegmentRuleSet(input: unknown): SegmentRuleSet {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    invalid("Segment rules must be an object.");
  }

  const raw = input as Record<string, unknown>;
  if (raw.version !== 1) invalid("Unsupported segment rule version.");
  if (raw.match !== "all" && raw.match !== "any") {
    invalid("Segment match must be all or any.");
  }
  if (!Array.isArray(raw.rules) || raw.rules.length === 0 || raw.rules.length > 25) {
    invalid("A segment requires between 1 and 25 rules.");
  }

  const rules = raw.rules.map((item): SegmentRule => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      invalid("Segment rule must be an object.");
    }
    const row = item as Record<string, unknown>;
    if (typeof row.attribute !== "string") invalid("Segment attribute is required.");
    const attribute = row.attribute.trim();
    if (FORBIDDEN_ATTRIBUTE_PREFIXES.some((prefix) => attribute.startsWith(prefix))) {
      throw new ApiError(
        400,
        "segment_sensitive_attribute_forbidden",
        "Sensitive health attributes are not available for audience segmentation.",
      );
    }
    if (!ALLOWED_ATTRIBUTES.has(attribute as SegmentAttribute)) {
      invalid("Segment attribute is not supported.");
    }
    if (typeof row.operator !== "string" || !OPERATORS.has(row.operator as SegmentOperator)) {
      invalid("Segment operator is not supported.");
    }
    const operator = row.operator as SegmentOperator;
    return {
      attribute: attribute as SegmentAttribute,
      operator,
      value: validateValue(operator, row.value),
    };
  });

  return { version: 1, match: raw.match, rules };
}

export function canonicalSegmentRuleSet(ruleSet: SegmentRuleSet): string {
  return JSON.stringify({
    version: ruleSet.version,
    match: ruleSet.match,
    rules: ruleSet.rules.map((rule) => ({
      attribute: rule.attribute,
      operator: rule.operator,
      ...(rule.value === undefined ? {} : { value: rule.value }),
    })),
  });
}

export async function hashSegmentRuleSet(ruleSet: SegmentRuleSet): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalSegmentRuleSet(ruleSet));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((value) => value.toString(16).padStart(2, "0")).join("");
}
