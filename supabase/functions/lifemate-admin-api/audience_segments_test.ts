import {
  canonicalSegmentRuleSet,
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
