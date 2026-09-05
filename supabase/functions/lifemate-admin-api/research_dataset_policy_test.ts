import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
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
  assertThrows(() =>
    validateResearchPrivacyPolicy({
      ...policy,
      smallCellThreshold: 21,
    })
  );
});

Deno.test("research pseudonymous row export remains explicitly unavailable", () => {
  const error = assertThrows(() =>
    validateResearchPrivacyPolicy({
      ageBucketYears: 2,
      minimumCohortSize: 20,
      smallCellThreshold: 5,
      rowMode: "Pseudonymous",
    })
  );
  assertEquals(
    error instanceof Error ? error.message : String(error),
    "Pseudonymous row-level research export is not available yet.",
  );
});

Deno.test("research small cells are marked for suppression", () => {
  assertEquals(
    suppressSmallCells([
      { label: "20–22", count: 4 },
      { label: "22–24", count: 5 },
    ], 5),
    [
      { label: "20–22", count: 4, suppressed: true },
      { label: "22–24", count: 5, suppressed: false },
    ],
  );
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

Deno.test("research migrations enforce DB privacy and reviewed quasi transforms", async () => {
  const foundation = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827120000_research_dataset_builder_foundation.sql",
      import.meta.url,
    ),
  );
  const kind = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827120300_research_dataset_kind.sql",
      import.meta.url,
    ),
  );
  const quasi = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827120350_research_quasi_identifier_rules.sql",
      import.meta.url,
    ),
  );
  const preview = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827120400_research_health_observation_preview.sql",
      import.meta.url,
    ),
  );

  assertEquals(foundation.includes("admin.account_is_active_founder"), true);
  assertEquals(
    foundation.includes("revoke all on analytics.dataset_definitions"),
    true,
  );
  assertEquals(foundation.includes("direct_identifiers_removed=true"), true);
  assertEquals(foundation.includes("research_source_not_allowed"), true);
  assertEquals(
    foundation.includes("research_json_contains_direct_identifier"),
    true,
  );
  assertEquals(kind.includes("research_json_contains_direct_identifier"), true);
  assertEquals(quasi.includes("homeRegionMode"), true);
  assertEquals(quasi.includes("not in ('omit','country')"), true);
  assertEquals(preview.includes("homeRegionMode','omit"), true);
  assertEquals(preview.includes("split_part"), true);
});
