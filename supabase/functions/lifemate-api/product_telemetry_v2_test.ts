import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  compareSemver,
  evaluateUpdatePolicy,
  parseProductVersionPresence,
  parseUpdatePolicyQuery,
} from "./product_telemetry_v2.ts";
import { ApiError } from "./validation.ts";

Deno.test("product version presence accepts only bounded low-cardinality metadata", () => {
  assertEquals(
    parseProductVersionPresence({
      product: "WellMate",
      platform: "Android",
      appVersion: "0.9.0-internal.9+20",
      buildNumber: "20",
      rolloutCohort: "beta-a",
    }),
    {
      product: "wellmate",
      platform: "android",
      appVersion: "0.9.0-internal.9+20",
      buildNumber: "20",
      rolloutCohort: "beta-a",
    },
  );

  const error = assertThrows(() =>
    parseProductVersionPresence({
      product: "wellmate",
      platform: "android",
      appVersion: "0.9.0",
      buildNumber: "20",
      deviceId: "forbidden-fingerprint",
    })
  );
  assertEquals(error instanceof ApiError, true);
  assertEquals((error as ApiError).code, "product_version_field_forbidden");
});

Deno.test("semantic version comparator handles prerelease and build metadata", () => {
  assertEquals(compareSemver("0.9.0-internal.9+20", "0.9.0"), -1);
  assertEquals(compareSemver("1.2.3+9", "1.2.3+10"), 0);
  assertEquals(compareSemver("1.2.4", "1.2.3"), 1);
  assertEquals(compareSemver("1.2.3-beta.2", "1.2.3-beta.10"), -1);
});

Deno.test("force update is only emitted for below-minimum critical policy", () => {
  assertEquals(
    evaluateUpdatePolicy({
      minimumSupportedVersion: "1.2.0",
      recommendedVersion: "1.3.0",
      mode: "Force",
      reasonCode: "Security",
      policyVersion: 4,
    }, "1.1.9").updateState,
    "force",
  );

  assertEquals(
    evaluateUpdatePolicy({
      minimumSupportedVersion: "1.2.0",
      recommendedVersion: "1.3.0",
      mode: "Soft",
      reasonCode: "Routine",
      policyVersion: 5,
    }, "1.1.9").updateState,
    "soft",
  );

  assertEquals(
    evaluateUpdatePolicy({
      minimumSupportedVersion: "1.2.0",
      recommendedVersion: "1.3.0",
      mode: "Force",
      reasonCode: "Security",
      policyVersion: 6,
    }, "1.3.0").updateState,
    "current",
  );
});

Deno.test("update policy query rejects non-semver client versions", () => {
  const error = assertThrows(() =>
    parseUpdatePolicyQuery(
      new URL(
        "https://example.test/api/v1/product/update-policy?product=wellmate&platform=android&currentVersion=latest",
      ),
    )
  );
  assertEquals(error instanceof ApiError, true);
  assertEquals((error as ApiError).code, "app_version_invalid");
});
