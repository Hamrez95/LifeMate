import { assert, assertStringIncludes } from "jsr:@std/assert";

Deno.test("manual entitlement mutation primitives are actor-aware and legacy grants are revoked", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827030500_manual_entitlement_mutation_guard.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "apply_manual_entitlement_grant_guarded");
  assertStringIncludes(migration, "apply_manual_entitlement_change_guarded");
  assertStringIncludes(
    migration,
    "admin.account_has_permission(p_actor_account_id,'commerce.entitlement.adjust.execute')",
  );
  assertStringIncludes(migration, "v_ent.source='FREE'");
  assertStringIncludes(
    migration,
    "revoke execute on function commerce.apply_manual_entitlement_grant",
  );
  assertStringIncludes(
    migration,
    "revoke execute on function commerce.apply_manual_entitlement_change",
  );
});

Deno.test("server orchestration uses guarded primitives and non-elevated audit semantics", async () => {
  const service = await Deno.readTextFile(
    new URL("./manual_entitlement_adjustments_service.ts", import.meta.url),
  );
  assertStringIncludes(
    service,
    "commerce.apply_manual_entitlement_grant_guarded",
  );
  assertStringIncludes(
    service,
    "commerce.apply_manual_entitlement_change_guarded",
  );
  assert(
    /entitlement-adjust:\$\{\s*input\.requestHash\.slice\(0,\s*48\)\s*\}/.test(
      service,
    ),
    "abuse idempotency must remain bound to the normalized request hash",
  );
  assert(
    /\$\{input\.idempotencyKey\},\s*false,/.test(service),
    "commerce audit must remain explicitly non-elevated",
  );
  assert(!service.includes("apply_manual_entitlement_grant(\n"));
  assert(!service.includes("apply_manual_entitlement_change(\n"));
});
