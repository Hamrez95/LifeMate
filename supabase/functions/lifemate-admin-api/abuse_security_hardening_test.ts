import { assert, assertStringIncludes } from "jsr:@std/assert";

Deno.test("abuse administration uses reachable high-risk RBAC and narrow writes", async () => {
  const hardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023500_abuse_security_hardening.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(hardening, "risk_level='HIGH_RISK'");
  assertStringIncludes(hardening, "role_assignable=true");
  assertStringIncludes(hardening, "security definer");
  assertStringIncludes(
    hardening,
    "revoke insert,update on security.abuse_rules from lifemate_admin_runtime",
  );
  assertStringIncludes(
    hardening,
    "revoke insert on security.abuse_rule_versions from lifemate_admin_runtime",
  );
});

Deno.test("generic edge runtime cannot evaluate arbitrary subjects or record abuse events directly", async () => {
  const hardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023500_abuse_security_hardening.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    hardening,
    "revoke execute on function security.evaluate_abuse_rules",
  );
  assertStringIncludes(hardening, "from lifemate_edge_runtime");
  assertStringIncludes(
    hardening,
    "revoke execute on function security.record_abuse_event",
  );
});

Deno.test("abuse admin routes share the bounded Admin database client", async () => {
  const routes = await Deno.readTextFile(
    new URL("./abuse_rules_routes.ts", import.meta.url),
  );
  assertStringIncludes(
    routes,
    'import { getAdminSql } from "./database_client.ts"',
  );
  assertStringIncludes(routes, "getAdminSql(databaseUrl)");
  assert(!routes.includes('import postgres from "postgres"'));
});

Deno.test("abuse rule mutations persist deterministic error outcomes for idempotent replay", async () => {
  const idempotency = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827023600_abuse_idempotency_outcome_hardening.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(idempotency, "status='Completed'");
  assertStringIncludes(idempotency, "response_status=v_status");
  assertStringIncludes(idempotency, "response_json=v_result");
  assert(!idempotency.includes("delete from admin.idempotency_keys"));
});
