import { assert, assertStringIncludes } from "jsr:@std/assert";

async function source(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(path, import.meta.url));
}

Deno.test("audience segment projection stays on canonical non-health sources", async () => {
  const text = await source("./audience_segments_service.ts");
  assertStringIncludes(text, "admin.user_directory_v2");
  assertStringIncludes(text, "core.person_profiles");
  assertStringIncludes(text, "commerce.subscriptions");
  assertStringIncludes(text, "commerce.entitlements");
  assertStringIncludes(text, "commerce.features");
  assert(!text.includes("lifemate.user_profiles"));
  assert(!text.includes("health."));
  assert(!text.includes("women_health."));
  assert(!text.includes("medication."));
});

Deno.test("missing engagement age stays unknown instead of becoming fabricated inactivity", async () => {
  const text = await source("./audience_segments_service.ts");
  assertStringIncludes(text, 'return { days: null, label: "never_active" }');
  assertStringIncludes(text, "if (activity.days !== null)");
  assert(!text.includes("36500"));
});

Deno.test("audience segment routes require purpose-specific permissions", async () => {
  const text = await source("./audience_segments_routes.ts");
  assertStringIncludes(
    text,
    'requirePermission(admin, "marketing.segment.read")',
  );
  assertStringIncludes(
    text,
    'requirePermission(admin, "marketing.segment.write")',
  );
  assert(!text.includes("service_role"));
  assert(!text.includes("supabase.from"));
});

Deno.test("audience migration is browser-denied, portable, deletion-compatible and history append-only", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260826231500_audience_segment_engine.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "force row level security");
  assertStringIncludes(migration, "revoke all on schema audience from public");
  assertStringIncludes(migration, "to_regrole('anon') is not null");
  assertStringIncludes(migration, "to_regrole('authenticated') is not null");
  assertStringIncludes(
    migration,
    "execute 'revoke all on schema audience from anon'",
  );
  assertStringIncludes(
    migration,
    "execute 'revoke all on schema audience from authenticated'",
  );
  assertStringIncludes(migration, "account_id uuid not null,");
  assertStringIncludes(migration, "security definer");
  assertStringIncludes(
    migration,
    "grant select on audience.segment_history to lifemate_admin_runtime",
  );
  assert(
    !migration.includes("grant select,insert on audience.segment_history"),
  );
  assert(
    !migration.includes(
      "account_id uuid not null references identity.accounts(id)",
    ),
  );
});

Deno.test("small audience snapshots are suppressed in API responses", async () => {
  const text = await source("./audience_segments_routes.ts");
  assertStringIncludes(text, "memberCount: suppressed ? null : exactCount");
  assertStringIncludes(text, "minimumCohortSize: MIN_PREVIEW_COHORT");
});

Deno.test("execution snapshots validate and persist under one database transaction", async () => {
  const routes = await source("./audience_segments_routes.ts");
  const service = await source("./audience_segments_service.ts");
  assertStringIncludes(routes, "parseSnapshotExpectedVersion");
  assertStringIncludes(routes, "expectedVersion,");
  assertStringIncludes(
    routes,
    "hashSnapshotRequest(snapshotId, expectedVersion, idempotencyKey)",
  );
  assert(!routes.includes("withActiveSegmentVersionLock"));
  assertStringIncludes(service, "for share");
  assertStringIncludes(service, 'segment.status !== "Active"');
  assertStringIncludes(service, "segment.version !== input.expectedVersion");
  assertStringIncludes(service, '"segment_version_conflict"');
  assertStringIncludes(service, '"segment_not_active"');
  assertStringIncludes(service, "matchingMembers(segment.ruleSet, tx)");
  assertStringIncludes(service, "Admin pool is intentionally max=1");
});

Deno.test("audience segment workflow uses canonical idempotency and audit enum values", async () => {
  const text = await source("./audience_segments_service.ts");
  assertStringIncludes(text, "'Processing'");
  assertStringIncludes(text, "'Completed'");
  assertStringIncludes(text, "'Succeeded'");
  assert(!text.includes("'Pending'"));
  assert(!text.includes("'success'"));
});
