import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  hashAbuseRuleMutation,
  matchAbuseRuleRetirePath,
  parseAbuseRuleMutation,
  parseAbuseRuleRetire,
} from "./abuse_rules.ts";
import { ApiError } from "./validation.ts";

function request(body: unknown): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("velocity rule request is typed, bounded and hash stable", async () => {
  const payload = await parseAbuseRuleMutation(request({
    code: "gift.daily_velocity",
    contextCode: "gift.purchase",
    displayName: "Gift purchase daily velocity",
    ruleKind: "VelocityLimit",
    subjectScope: "Account",
    enforcementAction: "Deny",
    windowSeconds: 86400,
    maxCount: 10,
    cooldownSeconds: null,
    evidenceCode: null,
    approvalRequestType: null,
    priority: 20,
    expectedVersion: null,
    reason: "Limit repeated gift purchases with an explainable daily rule.",
  }));
  assertEquals(payload.contextCode, "gift.purchase");
  assertEquals(payload.maxCount, 10);
  const first = await hashAbuseRuleMutation(payload);
  const second = await hashAbuseRuleMutation(payload);
  assertEquals(first, second);
  assert(/^[0-9a-f]{64}$/.test(first));
});

Deno.test("RequireApproval is explicit and cannot omit approval policy", async () => {
  const error = await assertRejects(
    () =>
      parseAbuseRuleMutation(request({
        code: "refund.manual_review",
        contextCode: "refund.request",
        displayName: "Refund manual review",
        ruleKind: "UsageCap",
        subjectScope: "Account",
        enforcementAction: "RequireApproval",
        maxCount: 3,
        priority: 10,
        expectedVersion: null,
        reason:
          "Route repeated refund requests through a configured approval policy.",
      })),
    ApiError,
  );
  assertEquals(error.code, "approval_request_type_invalid");
});

Deno.test("rule parameter shapes fail closed", async () => {
  const error = await assertRejects(
    () =>
      parseAbuseRuleMutation(request({
        code: "gift.bad_shape",
        contextCode: "gift.purchase",
        displayName: "Bad rule",
        ruleKind: "Cooldown",
        subjectScope: "Account",
        enforcementAction: "Deny",
        maxCount: 2,
        cooldownSeconds: null,
        priority: 100,
        expectedVersion: null,
        reason:
          "Reject a malformed cooldown rule instead of silently ignoring it.",
      })),
    ApiError,
  );
  assertEquals(error.code, "abuse_rule_shape_invalid");
});

Deno.test("retire route and payload require concurrency", async () => {
  const id = "123e4567-e89b-42d3-a456-426614174000";
  assertEquals(
    matchAbuseRuleRetirePath(
      `/api/v1/security/abuse/rules/${id}/actions/retire`,
    ),
    id,
  );
  const parsed = await parseAbuseRuleRetire(request({
    expectedVersion: 4,
    reason: "Retire this rule after the campaign workflow is removed.",
  }));
  assertEquals(parsed.expectedVersion, 4);
});

Deno.test("abuse engine stores hashes instead of contact plaintext", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023000_explainable_abuse_rules.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "normalized_value_hash");
  assertStringIncludes(migration, "verified_at_utc is not null");
  assertStringIncludes(migration, "subject_key_hash");
  assertStringIncludes(migration, "extensions.digest");
  assert(!migration.includes("encrypted_value"));
  assert(!migration.includes("phone_number"));
  assert(!migration.includes("health_observation"));
  assert(!migration.includes("medication"));
});

Deno.test("abuse engine is explainable, idempotent and non-punitive", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023000_explainable_abuse_rules.sql",
      import.meta.url,
    ),
  );
  const hardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023100_abuse_rule_hardening.sql",
      import.meta.url,
    ),
  );
  const idempotency = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023200_abuse_rule_idempotency.sql",
      import.meta.url,
    ),
  );
  const priority = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023300_abuse_evaluator_priority.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "('Allow','Deny','RequireApproval')");
  assertStringIncludes(migration, "matched_rule_ids");
  assertStringIncludes(migration, "reason_codes");
  assertStringIncludes(migration, "approval_request_type");
  assertStringIncludes(
    hardening,
    "on conflict(context_code,subject_scope,subject_key_hash,operation_key_hash,event_code) do nothing",
  );
  assertStringIncludes(idempotency, "admin.idempotency_keys");
  assertStringIncludes(
    priority,
    "v_rule.enforcement_action='RequireApproval' and v_final='Allow'",
  );
  assert(!migration.toLowerCase().includes("machine learning"));
  assert(!migration.toLowerCase().includes("suspend account"));
});

Deno.test("abuse administration is HIGH_RISK and uses narrow server entrypoints", async () => {
  const securityHardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023500_abuse_security_hardening.sql",
      import.meta.url,
    ),
  );
  const routes = await Deno.readTextFile(
    new URL("./abuse_rules_routes.ts", import.meta.url),
  );
  assertStringIncludes(securityHardening, "risk_level='HIGH_RISK'");
  assertStringIncludes(securityHardening, "role_assignable=true");
  assertStringIncludes(securityHardening, "security definer");
  assertStringIncludes(
    securityHardening,
    "revoke insert,update on security.abuse_rules from lifemate_admin_runtime",
  );
  assertStringIncludes(
    securityHardening,
    "revoke execute on function security.evaluate_abuse_rules",
  );
  assertStringIncludes(securityHardening, "from lifemate_edge_runtime");
  assertStringIncludes(
    routes,
    'import { getAdminSql } from "./database_client.ts"',
  );
  assertStringIncludes(routes, "const sql = getAdminSql(databaseUrl)");
  assert(!routes.includes('import postgres from "postgres"'));
});

Deno.test("abuse tables have no browser grants and edge uses functions only", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023000_explainable_abuse_rules.sql",
      import.meta.url,
    ),
  );
  const hardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023100_abuse_rule_hardening.sql",
      import.meta.url,
    ),
  );
  const routes = await Deno.readTextFile(
    new URL("./abuse_rules_routes.ts", import.meta.url),
  );
  assertStringIncludes(migration, "force row level security");
  assertStringIncludes(
    migration,
    "revoke all on table security.abuse_rules from public,anon,authenticated",
  );
  assertStringIncludes(
    hardening,
    "revoke all on table security.abuse_events from lifemate_edge_runtime",
  );
  assertStringIncludes(
    hardening,
    "revoke all on table security.abuse_decisions from lifemate_edge_runtime",
  );
  assert(!routes.includes("service_role"));
  assert(!routes.includes("supabase.from"));
});
