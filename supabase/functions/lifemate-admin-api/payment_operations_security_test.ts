import { assertStringIncludes } from "jsr:@std/assert";

Deno.test("generic edge runtime cannot spoof renewal-intent actors", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032700_payment_operations_security_boundary.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    migration,
    "revoke execute on function commerce.set_subscription_renewal_intent_v2",
  );
  assertStringIncludes(migration, "from lifemate_edge_runtime");
  assertStringIncludes(migration, "to lifemate_admin_runtime");
});

Deno.test("commerce audits cannot masquerade as elevated-health access", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032700_payment_operations_security_boundary.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "enforce_commerce_audit_elevation_semantics");
  assertStringIncludes(migration, "'commerce.refund.execute'");
  assertStringIncludes(migration, "'commerce.reconciliation.open'");
  assertStringIncludes(migration, "'commerce.reconciliation.correct'");
  assertStringIncludes(migration, "new.elevated_access:=false");
});
