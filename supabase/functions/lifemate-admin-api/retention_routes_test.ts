import { assert, assertStringIncludes } from "jsr:@std/assert";

Deno.test("retention v3 extends existing lifecycle model without browser grants", async () => {
  const migration = await Deno.readTextFile(
    new URL("../../migrations/20260827021000_data_lifecycle_retention_v3.sql", import.meta.url),
  );
  assertStringIncludes(migration, "alter table security.retention_policies");
  assertStringIncludes(migration, "security.retention_policy_versions");
  assertStringIncludes(migration, "security.retention_holds");
  assertStringIncludes(migration, "security.retention_execution_runs");
  assertStringIncludes(migration, "force row level security");
  assertStringIncludes(migration, "revoke all on table security.retention_holds from public,anon,authenticated");
  assert(!migration.includes("grant select on security.retention_holds to authenticated"));
});

Deno.test("account deletion gate runs before destructive database finalization", async () => {
  const gate = await Deno.readTextFile(
    new URL("../../migrations/20260827021100_data_lifecycle_deletion_gate.sql", import.meta.url),
  );
  const holdRace = await Deno.readTextFile(
    new URL("../../migrations/20260827021200_retention_hold_claim_race.sql", import.meta.url),
  );
  assertStringIncludes(gate, "identity.account_deletion_block_until");
  assertStringIncludes(gate, "integration.gate_account_deletion_outbox");
  assertStringIncludes(gate, "before insert or update of available_at_utc,status on integration.outbox_messages");
  assertStringIncludes(gate, "identity.account_deletion_execution_eligibility(new.id)");
  assertStringIncludes(holdRace, "retention_deletion_in_progress");
  assertStringIncludes(holdRace, "status in ('Pending','Failed','Processing')");
  assertStringIncludes(holdRace, "for update");
});

Deno.test("retention admin API is permissioned and preview is non-destructive", async () => {
  const routes = await Deno.readTextFile(new URL("./retention_routes.ts", import.meta.url));
  assertStringIncludes(routes, 'requirePermission(admin, "security.retention.read")');
  assertStringIncludes(routes, 'requirePermission(admin, "security.retention.write")');
  assertStringIncludes(routes, 'destructiveActionPerformed: false');
  assertStringIncludes(routes, 'security.activate_retention_policy');
  assertStringIncludes(routes, 'security.create_retention_hold');
  assertStringIncludes(routes, 'security.release_retention_hold');
  assert(!routes.includes("service_role"));
  assert(!routes.includes("supabase.from"));
});

Deno.test("subscription expiry is not used as an account deletion trigger", async () => {
  const routes = await Deno.readTextFile(new URL("./retention_routes.ts", import.meta.url));
  const migration = await Deno.readTextFile(
    new URL("../../migrations/20260827021000_data_lifecycle_retention_v3.sql", import.meta.url),
  );
  assert(!routes.includes("subscription_expired"));
  assert(!migration.includes("delete from commerce.subscriptions"));
  assert(!migration.includes("delete from commerce.entitlements"));
});
