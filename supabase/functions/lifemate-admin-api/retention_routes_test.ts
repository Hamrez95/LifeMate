import { assert, assertStringIncludes } from "jsr:@std/assert";

Deno.test("retention v3 extends existing lifecycle model without browser grants", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827021000_data_lifecycle_retention_v3.sql",
      import.meta.url,
    ),
  );
  const hardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827021400_retention_security_hardening.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "alter table security.retention_policies");
  assertStringIncludes(migration, "security.retention_policy_versions");
  assertStringIncludes(migration, "security.retention_holds");
  assertStringIncludes(migration, "security.retention_execution_runs");
  assertStringIncludes(migration, "force row level security");
  assertStringIncludes(
    migration,
    "revoke all on table security.retention_holds from public,anon,authenticated",
  );
  assertStringIncludes(hardening, "risk_level='HIGH_RISK'");
  assertStringIncludes(hardening, "role_assignable=true");
  assertStringIncludes(hardening, "security definer");
  assertStringIncludes(
    hardening,
    "revoke insert,update on security.retention_holds from lifemate_admin_runtime",
  );
  assert(
    !migration.includes(
      "grant select on security.retention_holds to authenticated",
    ),
  );
});

Deno.test("account deletion gate runs before destructive database finalization and preserves policy evidence", async () => {
  const gate = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827021100_data_lifecycle_deletion_gate.sql",
      import.meta.url,
    ),
  );
  const holdRace = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827021200_retention_hold_claim_race.sql",
      import.meta.url,
    ),
  );
  const versionPreservation = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827021600_retention_policy_version_preservation.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(gate, "identity.account_deletion_block_until");
  assertStringIncludes(gate, "integration.gate_account_deletion_outbox");
  assertStringIncludes(
    gate,
    "before insert or update of available_at_utc,status on integration.outbox_messages",
  );
  assertStringIncludes(
    gate,
    "identity.account_deletion_execution_eligibility(new.id)",
  );
  assertStringIncludes(holdRace, "retention_deletion_in_progress");
  assertStringIncludes(holdRace, "status in ('Pending','Failed','Processing')");
  assertStringIncludes(holdRace, "for update");
  assertStringIncludes(
    versionPreservation,
    "preserve_account_deletion_retention_policy_version",
  );
  assertStringIncludes(
    versionPreservation,
    "old.retention_policy_version like 'retention-v3.%'",
  );
  assertStringIncludes(
    versionPreservation,
    "new.retention_policy_version in ('retention-v1','retention-v2')",
  );
});

Deno.test("retention admin API is permissioned, bounded and idempotent", async () => {
  const routes = await Deno.readTextFile(
    new URL("./retention_routes.ts", import.meta.url),
  );
  const idempotency = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827021500_retention_idempotent_mutations.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin, "security.retention.read")',
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin, "security.retention.write")',
  );
  assertStringIncludes(routes, "getAdminSql(databaseUrl)");
  assertStringIncludes(routes, "requireIdempotencyKey(request)");
  assertStringIncludes(routes, "destructiveActionPerformed: false");
  assertStringIncludes(routes, "security.activate_retention_policy_idempotent");
  assertStringIncludes(routes, "security.create_retention_hold_idempotent");
  assertStringIncludes(routes, "security.release_retention_hold_idempotent");
  assertStringIncludes(idempotency, "idempotency_conflict");
  assertStringIncludes(idempotency, "'Processing'");
  assertStringIncludes(idempotency, "'Completed'");
  assert(!routes.includes('import postgres from "postgres"'));
  assert(!routes.includes("service_role"));
  assert(!routes.includes("supabase.from"));
});

Deno.test("subscription expiry is not used as an account deletion trigger", async () => {
  const routes = await Deno.readTextFile(
    new URL("./retention_routes.ts", import.meta.url),
  );
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827021000_data_lifecycle_retention_v3.sql",
      import.meta.url,
    ),
  );
  assert(!routes.includes("subscription_expired"));
  assert(!migration.includes("delete from commerce.subscriptions"));
  assert(!migration.includes("delete from commerce.entitlements"));
});
