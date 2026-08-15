import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

const repoRoot = new URL("../../", import.meta.url);

async function read(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(path, repoRoot));
}

Deno.test("portable export bounds and exclusions match the reviewed privacy contract", async () => {
  const runtime = await read("supabase/functions/lifemate-api/data_export.ts");
  const contract = await read("docs/privacy/SELF_SERVICE_DATA_LIFECYCLE.md");

  assert(
    runtime.includes(
      'portableExportSchemaVersion = "lifemate-portable-export-v1"',
    ),
  );
  assert(runtime.includes("portableExportRowLimit = 20_000"));
  assert(runtime.includes("portableExportMaximumBytes = 8 * 1024 * 1024"));
  assert(runtime.includes('"raw authentication/provider subjects"'));
  assert(runtime.includes('"encrypted contact values and contact hashes"'));
  assert(runtime.includes('"raw identifiers belonging to linked people"'));
  assert(runtime.includes('"internal audit/security logs"'));
  assert(runtime.includes('"idempotency keys and outbox transport records"'));

  for (
    const phrase of [
      "lifemate-portable-export-v1",
      "maximum 20,000 rows",
      "8 MiB",
      "raw authentication/provider subjects",
      "internal audit/security logs",
      "raw identifiers belonging to linked people",
      "idempotency keys/cached response records",
      "outbox transport records",
    ]
  ) {
    assert(contract.includes(phrase), `privacy contract is missing: ${phrase}`);
  }
});

Deno.test("product export wording describes portable JSON and clipboard handling without claiming a raw database dump", async () => {
  const ui = await read(
    "packages/lifemate_ui/lib/src/shared_profile_screen.dart",
  );

  assert(ui.includes("fa: 'دریافت نسخه‌ای از داده‌های من'"));
  assert(ui.includes("en: 'Export my data'"));
  assert(ui.includes("کپی JSON"));
  assert(ui.includes("device clipboard"));
  assert(!ui.includes("Export all database data"));
  assert(!ui.includes("خروجی کامل دیتابیس"));
});

Deno.test("privacy product actions stay wired to no-store lifecycle routes", async () => {
  const api = await read("supabase/functions/lifemate-api/index.ts");
  const http = await read("supabase/functions/lifemate-api/http.ts");
  const client = await read(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
  );

  assert(
    api.includes(
      'request.method === "GET" && path === "/api/v1/account/data-export"',
    ),
    "portable export route must remain registered",
  );
  assert(
    api.includes(
      'path === "/api/v1/account/deletion-requests/latest"',
    ),
    "deletion-status route must remain registered",
  );
  assert(
    api.includes('path === "/api/v1/account/deletion-requests"'),
    "deletion-request route must remain registered",
  );
  assert(
    api.includes("return json(exported, 200, {"),
    "portable export must continue through the shared JSON response helper",
  );
  assert(
    http.includes('"Cache-Control": "no-store"'),
    "privacy responses must retain the shared no-store response header",
  );

  assert(
    client.includes(
      "_asObject(await _send('GET', '/api/v1/account/data-export'))",
    ),
    "client export action must call the canonical portable-export route",
  );
  assert(
    client.includes(
      "_asObject(await _send('POST', '/api/v1/account/deletion-requests'))",
    ),
    "client deletion action must call the canonical deletion route",
  );
  assert(
    client.includes("'/api/v1/account/deletion-requests/latest'"),
    "client deletion status must call the canonical latest-request route",
  );
});

Deno.test("account deletion UI is bound to the runtime retention-v2 lifecycle", async () => {
  const ui = await read(
    "packages/lifemate_client/lib/src/account_deletion_action.dart",
  );
  const accountLifecycle = await read(
    "supabase/functions/lifemate-api/account_lifecycle.ts",
  );
  const worker = await read("supabase/functions/lifemate-worker/index.ts");
  const retentionMigration = await read(
    "supabase/migrations/20260814215000_account_deletion_retention_v2.sql",
  );
  const retention = await read("docs/privacy/ACCOUNT_DELETION_RETENTION.md");
  const contract = await read("docs/privacy/SELF_SERVICE_DATA_LIFECYCLE.md");

  assert(
    ui.includes(
      "Continuing immediately disables the account and revokes access.",
    ),
  );
  assert(ui.includes("owned health and women-calendar data"));
  assert(ui.includes("sign-in identifiers and profile files"));
  assert(
    ui.includes(
      "minimum pseudonymous records required for security, consent, shared-data integrity or legal retention",
    ),
  );

  assert(
    accountLifecycle.includes("identity.account_id_for_legacy_app_user"),
    "account lifecycle must resolve AppUser to Account before deletion",
  );
  assert(
    accountLifecycle.includes("identity.request_account_deletion"),
    "account lifecycle must use the canonical deletion request function",
  );
  assert(
    worker.includes('case "identity.account_deletion_requested"'),
    "worker must process the canonical account-deletion event",
  );
  assert(
    worker.includes("admin.auth.admin.deleteUser(authSubject, true)"),
    "worker must remove the provider auth identity before finalization",
  );
  assert(
    worker.includes("purgeProfilePhotoFolder"),
    "worker must purge server-owned profile storage before finalization",
  );
  assert(
    worker.includes("identity.finalize_account_deletion"),
    "worker must invoke the retention finalizer",
  );

  for (
    const marker of [
      "retention_policy_version = 'retention-v2'",
      "delete from lifemate.women_calendar_daily_logs",
      "delete from lifemate.health_observations",
      "delete from lifemate.treatment_plans",
      "delete from identity.contact_points",
      "delete from identity.external_identities",
      "metadata_json = jsonb_build_object('redacted','account_deleted')",
      "auth_subject = 'deleted:' || v_app_user_id::text",
      "grant execute on function identity.finalize_account_deletion(uuid) to lifemate_worker_runtime",
    ]
  ) {
    assert(
      retentionMigration.includes(marker),
      `retention-v2 runtime is missing: ${marker}`,
    );
  }

  assert(retention.includes("retention-v2"));
  assert(
    retention.includes("account IDs are **not** assumed to equal app-user IDs"),
  );
  assert(retention.includes("another patient"));
  assert(contract.includes("Account UUID, AppUser UUID and Person UUID"));
  assert(contract.includes("never assumed to be equal"));
});

Deno.test("technical privacy contract keeps jurisdiction-specific legal approval explicitly open", async () => {
  const retention = await read("docs/privacy/ACCOUNT_DELETION_RETENTION.md");
  const contract = await read("docs/privacy/SELF_SERVICE_DATA_LIFECYCLE.md");

  assert(retention.includes("jurisdiction-specific legal review"));
  assert(contract.includes("human/legal launch gates"));
  assertEquals(contract.includes("legal review is complete"), false);
});
