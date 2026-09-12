import {
  canonicalSegmentRuleSet,
  evaluateSegmentRuleSet,
  hashSegmentRuleSet,
  parseSegmentRuleSet,
} from "./audience_segments.ts";
import { ApiError } from "./validation.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("audience segments accept only the approved non-health rule DSL", () => {
  const parsed = parseSegmentRuleSet({
    version: 1,
    match: "all",
    rules: [
      { attribute: "product.code", operator: "eq", value: "wellmate_caremate" },
      { attribute: "subscription.status", operator: "in", value: ["active", "trial"] },
      { attribute: "engagement.last_active_days", operator: "lte", value: 30 },
    ],
  });
  assert(parsed.rules.length === 3, "expected three parsed rules");
  assert(parsed.match === "all", "expected all-match semantics");
});

Deno.test("audience segments accept bounded demographic age and birthday rules", () => {
  const parsed = parseSegmentRuleSet({
    version: 1,
    match: "all",
    rules: [
      { attribute: "demographic.age_years", operator: "gte", value: 18 },
      { attribute: "demographic.age_years", operator: "lte", value: 45 },
      { attribute: "demographic.birthday_upcoming_days", operator: "lte", value: 7 },
    ],
  });
  assert(parsed.rules.length === 3, "expected demographic rules");
  assert(
    evaluateSegmentRuleSet(parsed, {
      "demographic.age_years": 30,
      "demographic.birthday_upcoming_days": 2,
    }),
    "expected demographic subject to match",
  );
});

Deno.test("gender targeting requires explicit eq or in selection", () => {
  for (const operator of ["exists", "neq", "not_in"] as const) {
    let error: unknown;
    try {
      parseSegmentRuleSet({
        version: 1,
        match: "all",
        rules: [{
          attribute: "demographic.gender_identity",
          operator,
          ...(operator === "exists" ? {} : { value: operator === "not_in" ? ["man"] : "man" }),
        }],
      });
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof ApiError, `expected ${operator} gender rule to fail`);
    assert(error.code === "segment_rule_invalid", "unexpected gender validation code");
  }

  const parsed = parseSegmentRuleSet({
    version: 1,
    match: "all",
    rules: [{
      attribute: "demographic.gender_identity",
      operator: "in",
      value: ["woman", "prefer_not_to_say"],
    }],
  });
  assert(parsed.rules.length === 1, "explicit gender selection should be valid");
});

Deno.test("audience segments evaluate deterministic projected subjects", () => {
  const parsed = parseSegmentRuleSet({
    version: 1,
    match: "all",
    rules: [
      { attribute: "product.code", operator: "in", value: ["wellmate_caremate", "fitmate"] },
      { attribute: "subscription.status", operator: "eq", value: "active" },
      { attribute: "engagement.last_active_days", operator: "lte", value: 14 },
      { attribute: "entitlement.code", operator: "exists" },
    ],
  });
  assert(
    evaluateSegmentRuleSet(parsed, {
      "product.code": ["wellmate_caremate", "period_calendar"],
      "subscription.status": "active",
      "engagement.last_active_days": 8,
      "entitlement.code": ["care_core", "medications_plus"],
    }),
    "expected projected subject to match",
  );
  assert(
    !evaluateSegmentRuleSet(parsed, {
      "product.code": "wellmate_caremate",
      "subscription.status": "expired",
      "engagement.last_active_days": 8,
      "entitlement.code": "care_core",
    }),
    "expired subject must not match",
  );
});

Deno.test("audience segments reject health and treatment attributes", () => {
  for (const attribute of [
    "health.condition",
    "medication.name",
    "diagnosis.code",
    "treatment.status",
    "women_health.phase",
    "cycle.day",
  ]) {
    let error: unknown;
    try {
      parseSegmentRuleSet({
        version: 1,
        match: "all",
        rules: [{ attribute, operator: "eq", value: "x" }],
      });
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof ApiError, `expected ApiError for ${attribute}`);
    assert(error.code === "segment_sensitive_attribute_forbidden", `unexpected code for ${attribute}`);
  }
});

Deno.test("audience segment set operators are bounded", () => {
  let error: unknown;
  try {
    parseSegmentRuleSet({
      version: 1,
      match: "any",
      rules: [{ attribute: "product.code", operator: "in", value: [] }],
    });
  } catch (caught) {
    error = caught;
  }
  assert(error instanceof ApiError, "expected empty set to fail");
  assert(error.code === "segment_rule_invalid", "unexpected validation code");
});

Deno.test("audience demographic numeric ranges are bounded", () => {
  for (const [attribute, value] of [
    ["demographic.age_years", 131],
    ["demographic.birthday_month", 13],
    ["demographic.birthday_day", 32],
    ["demographic.birthday_upcoming_days", 367],
  ] as const) {
    let error: unknown;
    try {
      parseSegmentRuleSet({
        version: 1,
        match: "all",
        rules: [{ attribute, operator: "eq", value }],
      });
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof ApiError, `expected ${attribute} to be bounded`);
    assert(error.code === "segment_rule_invalid", "unexpected demographic validation code");
  }
});

Deno.test("audience segment range operators require finite numeric values", () => {
  for (const value of ["30", true, Number.NaN, Number.POSITIVE_INFINITY]) {
    let error: unknown;
    try {
      parseSegmentRuleSet({
        version: 1,
        match: "all",
        rules: [{ attribute: "engagement.last_active_days", operator: "lte", value }],
      });
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof ApiError, `expected invalid range value ${String(value)} to fail`);
    assert(error.code === "segment_rule_invalid", "unexpected range validation code");
  }
});

Deno.test("audience segment canonicalization and hash are deterministic", async () => {
  const parsed = parseSegmentRuleSet({
    version: 1,
    match: "all",
    rules: [
      { attribute: "demographic.locale", operator: "eq", value: "fa-IR" },
      { attribute: "product.enrolled", operator: "eq", value: true },
    ],
  });
  const canonical = canonicalSegmentRuleSet(parsed);
  const first = await hashSegmentRuleSet(parsed);
  const second = await hashSegmentRuleSet(parsed);
  assert(canonical.includes('"version":1'), "canonical form should contain the version");
  assert(first === second, "hash must be stable");
  assert(/^[a-f0-9]{64}$/.test(first), "hash must be lowercase SHA-256 hex");
});

Deno.test("exists rule cannot smuggle a value", () => {
  let error: unknown;
  try {
    parseSegmentRuleSet({
      version: 1,
      match: "all",
      rules: [{ attribute: "entitlement.code", operator: "exists", value: "unexpected" }],
    });
  } catch (caught) {
    error = caught;
  }
  assert(error instanceof ApiError, "expected exists-with-value to fail");
});
