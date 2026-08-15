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

Deno.test("account deletion UI matches retention-v2 owned-data deletion and pseudonymous-retention contract", async () => {
  const ui = await read(
    "packages/lifemate_client/lib/src/account_deletion_action.dart",
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
