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
  assertStringIncludes(text, 'if (activity.days !== null)');
  assert(!text.includes("36500"));
});

Deno.test("audience segment routes require purpose-specific permissions", async () => {
  const text = await source("./audience_segments_routes.ts");
  assertStringIncludes(text, 'requirePermission(admin,"marketing.segment.read")');
  assertStringIncludes(text, 'requirePermission(admin,"marketing.segment.write")');
  assert(!text.includes("service_role"));
  assert(!text.includes("supabase.from"));
});

Deno.test("audience migration is browser-denied and deletion-compatible", async () => {
  const migration = await Deno.readTextFile(
    new URL("../../migrations/20260826231500_audience_segment_engine.sql", import.meta.url),
  );
  assertStringIncludes(migration, "force row level security");
  assertStringIncludes(migration, "revoke all on schema audience from public, anon, authenticated");
  assertStringIncludes(migration, "account_id uuid not null,");
  assert(!migration.includes("account_id uuid not null references identity.accounts(id)"));
});

Deno.test("small audience snapshots are suppressed in API responses", async () => {
  const text = await source("./audience_segments_routes.ts");
  assertStringIncludes(text, "memberCount:suppressed ? null : exactCount");
  assertStringIncludes(text, "minimumCohortSize:MIN_PREVIEW_COHORT");
});

Deno.test("execution snapshots require the expected active segment version under a row lock", async () => {
  const routes = await source("./audience_segments_routes.ts");
  const guard = await source("./audience_segment_snapshot_guard.ts");
  assertStringIncludes(routes, "parseSnapshotExpectedVersion");
  assertStringIncludes(routes, "withActiveSegmentVersionLock");
  assertStringIncludes(routes, "hashSnapshotRequest(snapshotId,expectedVersion,idempotencyKey)");
  assertStringIncludes(guard, "for share");
  assertStringIncludes(guard, 'String(rows[0].status) !== "Active"');
  assertStringIncludes(guard, "Number(rows[0].version) !== expectedVersion");
  assertStringIncludes(guard, '"segment_version_conflict"');
  assertStringIncludes(guard, '"segment_not_active"');
});

Deno.test("audience segment workflow uses canonical idempotency and audit enum values", async () => {
  const text = await source("./audience_segments_service.ts");
  assertStringIncludes(text, "'Processing'");
  assertStringIncludes(text, "'Completed'");
  assertStringIncludes(text, "'Succeeded'");
  assert(!text.includes("'Pending'"));
  assert(!text.includes("'success'"));
});
