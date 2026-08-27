import {
  assertEquals,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  ageBucketLabel,
  assertCohortExportable,
  rejectDirectIdentifierFields,
  suppressSmallCells,
  validateResearchPrivacyPolicy,
} from "./research_dataset_policy.ts";

Deno.test("research age bucketing is configurable and deterministic", () => {
  assertEquals(ageBucketLabel(22, 2), "20–22");
  assertEquals(ageBucketLabel(21, 2), "20–22");
  assertEquals(ageBucketLabel(29, 5), "25–30");
});

Deno.test("research privacy thresholds fail closed", () => {
  const policy = validateResearchPrivacyPolicy({
    ageBucketYears: 2,
    minimumCohortSize: 20,
    smallCellThreshold: 5,
    rowMode: "Aggregate",
  });
  assertThrows(() => assertCohortExportable(19, policy));
  assertCohortExportable(20, policy);
  assertThrows(() => validateResearchPrivacyPolicy({
    ...policy,
    smallCellThreshold: 21,
  }));
});

Deno.test("research small cells are marked for suppression", () => {
  assertEquals(suppressSmallCells([
    { label: "20–22", count: 4 },
    { label: "22–24", count: 5 },
  ], 5), [
    { label: "20–22", count: 4, suppressed: true },
    { label: "22–24", count: 5, suppressed: false },
  ]);
});

Deno.test("research fields reject direct and linkable identifiers", () => {
  rejectDirectIdentifierFields(["age_bucket", "product_code", "cohort"]);
  assertThrows(() => rejectDirectIdentifierFields(["age_bucket", "email"]));
  assertThrows(() => rejectDirectIdentifierFields(["contact.phone_hash"]));
  assertThrows(() => rejectDirectIdentifierFields(["person_id"]));
  assertThrows(() => rejectDirectIdentifierFields(["account-id"]));
  assertThrows(() => rejectDirectIdentifierFields(["app_user_id"]));
  assertThrows(() => rejectDirectIdentifierFields(["emailAddress"]));
  assertThrows(() => rejectDirectIdentifierFields(["phoneNumber"]));
  assertThrows(() => rejectDirectIdentifierFields(["accountId"]));
  assertThrows(() => rejectDirectIdentifierFields(["authUserId"]));
});

Deno.test("research migration keeps founder-only function boundary", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827120000_research_dataset_builder_foundation.sql",
      import.meta.url,
    ),
  );
  assertEquals(migration.includes("admin.account_is_active_founder"), true);
  assertEquals(migration.includes("revoke all on analytics.dataset_definitions"), true);
  assertEquals(migration.includes("direct_identifiers_removed=true"), true);
  assertEquals(migration.includes("research_source_not_allowed"), true);
});
