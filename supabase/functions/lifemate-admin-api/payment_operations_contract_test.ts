import { assert, assertStringIncludes } from "jsr:@std/assert";

Deno.test("payment operations preserve provider facts and expose truthful read models", async () => {
  const foundation = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032000_payment_refund_churn_operations.sql",
      import.meta.url,
    ),
  );
  const routes = await Deno.readTextFile(
    new URL("./payment_operations_routes.ts", import.meta.url),
  );
  assertStringIncludes(foundation, "provider_normalized_status");
  assertStringIncludes(foundation, "effective_normalized_status");
  assertStringIncludes(foundation, "classification_source");
  assertStringIncludes(routes, "providerResultIsFactOnly: true");
  assertStringIncludes(routes, "providerFactsPreserved: true");
  assert(
    !foundation.includes("update commerce.transactions set normalized_status"),
  );
});

Deno.test("commerce dispatcher reaches refund and churn collection routes", async () => {
  const dispatcher = await Deno.readTextFile(
    new URL("./commerce_catalog_routes.ts", import.meta.url),
  );
  assertStringIncludes(dispatcher, 'path === "/api/v1/commerce/refunds"');
  assertStringIncludes(
    dispatcher,
    'path.startsWith("/api/v1/commerce/refunds/")',
  );
  assertStringIncludes(dispatcher, 'path === "/api/v1/commerce/churn"');
  assertStringIncludes(dispatcher, "paymentOperationsRouteHandler(input)");
});

Deno.test("refund execution never lets Admin fabricate provider success", async () => {
  const refund = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032100_refund_execution_contract.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(refund, "'PendingProvider'");
  assertStringIncludes(refund, "commerce.record_refund_provider_result");
  assertStringIncludes(refund, "to lifemate_worker_runtime");
  assert(
    !refund.includes(
      "grant execute on function commerce.record_refund_provider_result(uuid,character varying,character varying,character varying) to lifemate_admin_runtime",
    ),
  );
});

Deno.test("provider refund evidence is nonblank and terminal callbacks are conflict-safe", async () => {
  const hardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032600_refund_provider_result_idempotency.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(hardening, "provider_reference_required");
  assertStringIncludes(hardening, "provider_error_code_required");
  assertStringIncludes(hardening, "provider_result_conflict");
  assertStringIncludes(hardening, "provider_evidence_conflict");
  assertStringIncludes(
    hardening,
    "v_op.provider_reference_hash is distinct from v_reference_hash",
  );
  assertStringIncludes(
    hardening,
    "v_op.provider_error_code is distinct from v_error",
  );
  assertStringIncludes(hardening, "to lifemate_worker_runtime");
  assert(!hardening.includes("to lifemate_admin_runtime"));
});

Deno.test("partial refund is bounded by remaining succeeded-refund ledger", async () => {
  const refund = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032100_refund_execution_contract.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(refund, "remainingRefundableMinor");
  assertStringIncludes(refund, "filter(where ro.status='Succeeded')");
  assertStringIncludes(refund, "p_amount_minor>v_remaining");
  assertStringIncludes(refund, "commerce_refund_execution");
});

Deno.test("reconciliation corrections are append-only and v1 executor is revoked", async () => {
  const reconciliation = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032200_reconciliation_and_churn_contracts.sql",
      import.meta.url,
    ),
  );
  const idempotency = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032300_payment_operations_idempotency.sql",
      import.meta.url,
    ),
  );
  const cleanup = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032500_payment_operations_entrypoint_cleanup.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    reconciliation,
    "insert into commerce.transaction_corrections",
  );
  assertStringIncludes(idempotency, "apply_approved_transaction_correction_v2");
  assertStringIncludes(
    cleanup,
    "revoke all on function admin.apply_approved_transaction_correction",
  );
  assert(
    !reconciliation.includes(
      "update commerce.transactions set normalized_status",
    ),
  );
});

Deno.test("subscription cancellation stops renewal without ending entitlement", async () => {
  const reconciliation = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032200_reconciliation_and_churn_contracts.sql",
      import.meta.url,
    ),
  );
  const routes = await Deno.readTextFile(
    new URL("./payment_operations_routes.ts", import.meta.url),
  );
  assertStringIncludes(reconciliation, "cancel_at_period_end");
  assertStringIncludes(reconciliation, "entitlementChanged',false");
  assertStringIncludes(routes, "entitlementEndsAtPeriodEnd: true");
  assert(!reconciliation.includes("update commerce.entitlements"));
});

Deno.test("new operations stay behind split permissions and server-only routes", async () => {
  const foundation = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827032000_payment_refund_churn_operations.sql",
      import.meta.url,
    ),
  );
  const routes = await Deno.readTextFile(
    new URL("./payment_operations_routes.ts", import.meta.url),
  );
  assertStringIncludes(foundation, "commerce.refund.request");
  assertStringIncludes(foundation, "commerce.refund.execute");
  assertStringIncludes(foundation, "commerce.reconciliation.write");
  assertStringIncludes(foundation, "commerce.churn.read");
  assertStringIncludes(
    routes,
    'requirePermission(admin, "commerce.refund.read")',
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin, "commerce.reconciliation.read")',
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin, "commerce.churn.read")',
  );
  assert(!routes.includes("service_role"));
  assert(!routes.includes("supabase.from"));
});
