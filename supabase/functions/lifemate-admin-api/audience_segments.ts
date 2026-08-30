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
  | "demographic.age_years"
  | "demographic.age_bucket"
  | "demographic.birthday_month"
  | "demographic.birthday_day"
  | "demographic.birthday_upcoming_days"
  | "demographic.gender_identity"
  | "demographic.locale"
  | "product.code"
  | "product.enrolled"
  | "subscription.status"
  | "entitlement.code"
  | "engagement.lifecycle"
  | "engagement.last_active_days"
  | "campaign.channel"
  | "campaign.last_outcome";

export type SegmentScalar = string | number | boolean;

export type SegmentRule = {
  attribute: SegmentAttribute;
  operator: SegmentOperator;
  value?: SegmentScalar | SegmentScalar[];
};

export type SegmentRuleSet = {
  version: 1;
  match: "all" | "any";
  rules: SegmentRule[];
};

export type SegmentSubject = Partial<
  Record<SegmentAttribute, SegmentScalar | SegmentScalar[]>
>;

const ALLOWED_ATTRIBUTES = new Set<SegmentAttribute>([
  "demographic.age_years",
  "demographic.age_bucket",
  "demographic.birthday_month",
  "demographic.birthday_day",
  "demographic.birthday_upcoming_days",
  "demographic.gender_identity",
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

const GENDER_VALUES = new Set([
  "woman",
  "man",
  "non_binary",
  "self_describe",
  "prefer_not_to_say",
]);

function invalid(message: string): never {
  throw new ApiError(400, "segment_rule_invalid", message);
}

function isScalar(value: unknown): value is SegmentScalar {
  return typeof value === "string" || typeof value === "number" ||
    typeof value === "boolean";
}

function validateValue(
  operator: SegmentOperator,
  value: unknown,
): SegmentRule["value"] {
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
  if (operator === "gte" || operator === "lte") {
    if (typeof value !== "number" || !Number.isFinite(value)) {
      invalid("Range operators require a finite numeric value.");
    }
    return value;
  }
  if (!isScalar(value)) invalid("Segment rule value must be scalar.");
  return value;
}

function numericValues(value: SegmentRule["value"]): number[] {
  const values = Array.isArray(value) ? value : [value];
  if (values.some((item) => typeof item !== "number" || !Number.isInteger(item))) {
    invalid("Demographic numeric values must be integers.");
  }
  return values as number[];
}

function validateDemographicRule(
  attribute: SegmentAttribute,
  operator: SegmentOperator,
  value: SegmentRule["value"],
): void {
  if (attribute === "demographic.gender_identity") {
    if (operator !== "eq" && operator !== "in") {
      invalid("Gender audience rules require an explicit eq or in selection.");
    }
    const values = Array.isArray(value) ? value : [value];
    if (
      values.length === 0 ||
      values.some((item) => typeof item !== "string" || !GENDER_VALUES.has(item))
    ) {
      invalid("Gender audience value is not supported.");
    }
    return;
  }

  const ranges: Partial<
    Record<SegmentAttribute, { min: number; max: number }>
  > = {
    "demographic.age_years": { min: 0, max: 130 },
    "demographic.birthday_month": { min: 1, max: 12 },
    "demographic.birthday_day": { min: 1, max: 31 },
    "demographic.birthday_upcoming_days": { min: 0, max: 366 },
  };
  const range = ranges[attribute];
  if (!range || operator === "exists") return;
  const values = numericValues(value);
  if (values.some((item) => item < range.min || item > range.max)) {
    invalid(`${attribute} is outside its supported range.`);
  }
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
  if (
    !Array.isArray(raw.rules) || raw.rules.length === 0 ||
    raw.rules.length > 25
  ) {
    invalid("A segment requires between 1 and 25 rules.");
  }

  const rules = raw.rules.map((item): SegmentRule => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      invalid("Segment rule must be an object.");
    }
    const row = item as Record<string, unknown>;
    if (typeof row.attribute !== "string") {
      invalid("Segment attribute is required.");
    }
    const attribute = row.attribute.trim();
    if (
      FORBIDDEN_ATTRIBUTE_PREFIXES.some((prefix) =>
        attribute.startsWith(prefix)
      )
    ) {
      throw new ApiError(
        400,
        "segment_sensitive_attribute_forbidden",
        "Sensitive health attributes are not available for audience segmentation.",
      );
    }
    if (!ALLOWED_ATTRIBUTES.has(attribute as SegmentAttribute)) {
      invalid("Segment attribute is not supported.");
    }
    if (
      typeof row.operator !== "string" ||
      !OPERATORS.has(row.operator as SegmentOperator)
    ) {
      invalid("Segment operator is not supported.");
    }
    const operator = row.operator as SegmentOperator;
    const value = validateValue(operator, row.value);
    validateDemographicRule(attribute as SegmentAttribute, operator, value);
    return {
      attribute: attribute as SegmentAttribute,
      operator,
      value,
    };
  });

  return { version: 1, match: raw.match, rules };
}

function scalarEquals(left: SegmentScalar, right: SegmentScalar): boolean {
  return typeof left === typeof right && left === right;
}

function includesScalar(
  haystack: SegmentScalar[],
  needle: SegmentScalar,
): boolean {
  return haystack.some((value) => scalarEquals(value, needle));
}

export function evaluateSegmentRule(
  rule: SegmentRule,
  subject: SegmentSubject,
): boolean {
  const actual = subject[rule.attribute];
  if (rule.operator === "exists") return actual !== undefined;
  if (actual === undefined || rule.value === undefined) return false;

  const actualValues = Array.isArray(actual) ? actual : [actual];
  if (rule.operator === "eq" || rule.operator === "neq") {
    if (Array.isArray(rule.value)) return false;
    const matched = actualValues.some((value) =>
      scalarEquals(value, rule.value as SegmentScalar)
    );
    return rule.operator === "eq" ? matched : !matched;
  }

  if (rule.operator === "in" || rule.operator === "not_in") {
    if (!Array.isArray(rule.value)) return false;
    const matched = actualValues.some((value) =>
      includesScalar(rule.value as SegmentScalar[], value)
    );
    return rule.operator === "in" ? matched : !matched;
  }

  if (Array.isArray(rule.value) || actualValues.length !== 1) return false;
  const [single] = actualValues;
  if (typeof single !== "number" || typeof rule.value !== "number") return false;
  return rule.operator === "gte"
    ? single >= rule.value
    : single <= rule.value;
}

export function evaluateSegmentRuleSet(
  ruleSet: SegmentRuleSet,
  subject: SegmentSubject,
): boolean {
  const results = ruleSet.rules.map((rule) =>
    evaluateSegmentRule(rule, subject)
  );
  return ruleSet.match === "all" ? results.every(Boolean) : results.some(Boolean);
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

export async function hashSegmentRuleSet(
  ruleSet: SegmentRuleSet,
): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalSegmentRuleSet(ruleSet));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}
