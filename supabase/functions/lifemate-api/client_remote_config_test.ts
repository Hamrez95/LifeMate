import { assertEquals, assertThrows } from "jsr:@std/assert";
import {
  failClosedClientRuntimeConfig,
  isFailClosedControlPlaneError,
  parseClientRuntimeConfigQuery,
  withProtectedFailClosedDefaults,
} from "./client_remote_config.ts";

Deno.test("client runtime config accepts bounded product platform version and beta", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=WellMate&platform=android&currentVersion=1.2.3-beta.1%2B42&beta=true",
  );
  assertEquals(parseClientRuntimeConfigQuery(url), {
    product: "wellmate",
    platform: "android",
    currentVersion: "1.2.3-beta.1+42",
    beta: true,
  });
});

Deno.test("client runtime config rejects unknown products", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=unknown&platform=android&currentVersion=1.2.3",
  );
  assertThrows(() => parseClientRuntimeConfigQuery(url));
});

Deno.test("client runtime config rejects malformed versions", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=caremate&platform=android&currentVersion=latest",
  );
  assertThrows(() => parseClientRuntimeConfigQuery(url));
});

Deno.test("client runtime config rejects arbitrary beta values", () => {
  const url = new URL(
    "https://example.test/api/v1/product/runtime-config?product=caremate&platform=android&currentVersion=1.0.0&beta=yes",
  );
  assertThrows(() => parseClientRuntimeConfigQuery(url));
});

Deno.test("missing protected controls are inserted disabled and fail closed", () => {
  const controls = withProtectedFailClosedDefaults([
    {
      key: "client.women_calendar.enabled",
      kind: "FeatureFlag",
      valueType: "Boolean",
      value: true,
      definitionVersion: 4,
      source: "default",
      ruleVersion: null,
      failClosed: true,
    },
  ]);

  assertEquals(controls.length, 2);
  assertEquals(controls[0], {
    key: "client.women_calendar.enabled",
    kind: "FeatureFlag",
    valueType: "Boolean",
    value: true,
    definitionVersion: 4,
    source: "default",
    ruleVersion: null,
    failClosed: true,
  });
  assertEquals(controls[1], {
    key: "client.care_pairing.enabled",
    kind: "FeatureFlag",
    valueType: "Boolean",
    value: false,
    definitionVersion: 0,
    source: "missing_control",
    ruleVersion: null,
    failClosed: true,
  });
});

Deno.test("client runtime config recognizes only control-plane availability SQLSTATEs", () => {
  for (const code of ["3F000", "42P01", "42703", "42883", "42501"]) {
    assertEquals(isFailClosedControlPlaneError({ code }), true);
  }
  assertEquals(isFailClosedControlPlaneError({ code: "P0002" }), false);
  assertEquals(isFailClosedControlPlaneError({ code: "23505" }), false);
  assertEquals(isFailClosedControlPlaneError(new Error("boom")), false);
});

Deno.test("client runtime config fail-closed snapshot is a valid safe 200 payload", () => {
  const snapshot = failClosedClientRuntimeConfig({
    product: "wellmate",
    platform: "android",
    currentVersion: "0.9.0-internal.9+20",
  });

  assertEquals(snapshot.product, "wellmate");
  assertEquals(snapshot.platform, "android");
  assertEquals(snapshot.authoritative, "server_fail_closed");
  assertEquals(snapshot.cacheTtlSeconds, 15);
  assertEquals(snapshot.controls, [
    {
      key: "client.women_calendar.enabled",
      kind: "FeatureFlag",
      valueType: "Boolean",
      value: false,
      definitionVersion: 0,
      source: "server_fail_closed",
      ruleVersion: null,
      failClosed: true,
    },
    {
      key: "client.care_pairing.enabled",
      kind: "FeatureFlag",
      valueType: "Boolean",
      value: false,
      definitionVersion: 0,
      source: "server_fail_closed",
      ruleVersion: null,
      failClosed: true,
    },
  ]);
  assertEquals(snapshot.updatePolicy, {
    currentVersion: "0.9.0-internal.9+20",
    updateState: "current",
    forceUpdate: false,
    softUpdate: false,
    minimumSupportedVersion: null,
    recommendedVersion: null,
    mode: "Soft",
    reasonCode: "Unavailable",
    messageKey: null,
    policyVersion: 0,
  });
});
