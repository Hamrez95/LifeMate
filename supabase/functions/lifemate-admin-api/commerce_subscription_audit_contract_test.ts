import { assertFalse, assertStringIncludes } from "jsr:@std/assert@1";

const routes = await Deno.readTextFile(new URL("./commerce_trial_routes.ts", import.meta.url));
const store = await Deno.readTextFile(
  new URL("./commerce_subscription_audit_service.ts", import.meta.url),
);

Deno.test("conversion and gift audit reads require commerce.read", () => {
  assertStringIncludes(routes, 'path === "/api/v1/commerce/conversions"');
  assertStringIncludes(routes, 'path === "/api/v1/commerce/gifts"');
  assertStringIncludes(routes, 'requirePermission(admin, "commerce.read")');
});

Deno.test("gift audit output excludes claim secrets, phone hashes and reproductive-health fields", () => {
  assertFalse(store.includes("claim_token_hash"));
  assertFalse(store.includes("claimTokenHash"));
  assertFalse(store.includes("recipient_phone_hash"));
  assertFalse(store.includes("recipientPhoneHash"));
  assertFalse(/pregnan|menstrual|fertility|cycle_day|period_date/i.test(store));
  assertFalse(/relationship|consent|access_grant|health_payload/i.test(store));
  assertStringIncludes(store, "recipientAccountId");
  assertStringIncludes(store, "resultingSubscriptionId");
});

Deno.test("conversion audit is commercial provenance only", () => {
  assertStringIncludes(store, "sourceTransactionId");
  assertStringIncludes(store, "originalPaidMinor");
  assertStringIncludes(store, "transferredCreditMinor");
  assertStringIncludes(store, "idempotencyKey");
});
