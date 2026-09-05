import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  parseControlCreate,
  parseKillSwitchMutation,
  parseRuleMutation,
  platformRequestHash,
} from "./platform_controls_admin.ts";
import { ApiError } from "./validation.ts";

function request(body: unknown): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("feature flags are Boolean and mutation hash is stable", async () => {
  const payload = await parseControlCreate(request({
    controlKey: "wellmate.new_dashboard",
    controlKind: "FeatureFlag",
    valueType: "Boolean",
    defaultValue: false,
    description: "Enable the next WellMate dashboard presentation.",
    failClosed: true,
    reason: "Create a staged presentation flag without granting entitlement.",
  }));
  assertEquals(payload.defaultValue, false);
  const first = await platformRequestHash("platform.control.create", payload);
  const second = await platformRequestHash("platform.control.create", payload);
  assertEquals(first, second);
  assert(/^[0-9a-f]{64}$/.test(first));
});

Deno.test("feature flag cannot smuggle non-Boolean values", async () => {
  const error = await assertRejects(
    () =>
      parseControlCreate(request({
        controlKey: "wellmate.bad_flag",
        controlKind: "FeatureFlag",
        valueType: "String",
        defaultValue: "yes",
        description: "Invalid feature flag shape for regression coverage.",
        failClosed: true,
        reason: "Reject a flag that could bypass typed client assumptions.",
      })),
    ApiError,
  );
  assertEquals(error.code, "platform_feature_flag_type_invalid");
});

Deno.test("percentage rollout is bounded and typed", async () => {
  const parsed = await parseRuleMutation(
    request({
      priority: 10,
      targetType: "Percentage",
      targetKey: "staged-rollout-v1",
      rolloutBasisPoints: 2500,
      value: true,
      startsAtUtc: null,
      endsAtUtc: null,
      status: "Active",
      reason: "Roll out to a deterministic twenty-five percent cohort.",
    }),
    "Boolean",
    true,
  );
  assertEquals(parsed.rolloutBasisPoints, 2500);
  assertEquals(parsed.targetType, "Percentage");
});

Deno.test("kill switch requires optimistic concurrency", async () => {
  const error = await assertRejects(
    () =>
      parseKillSwitchMutation(request({
        expectedVersion: 0,
        reason: "Emergency disable after a critical compatibility defect.",
      })),
    ApiError,
  );
  assertEquals(error.code, "platform_expected_version_invalid");
});

Deno.test("Admin mutation boundary keeps browser roles denied and history append-only", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827221000_platform_controls_admin_mutation_boundary.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    migration,
    "grant select,insert,update on platform.controls to lifemate_admin_runtime",
  );
  assertStringIncludes(
    migration,
    "revoke update,delete on platform.control_history from lifemate_admin_runtime",
  );
  assertStringIncludes(
    migration,
    "revoke delete on platform.controls from lifemate_admin_runtime",
  );
  assert(!migration.includes("to anon"));
  assert(!migration.includes("to authenticated"));
});

Deno.test("Admin responses state that controls do not grant permission or entitlement", async () => {
  const route = await Deno.readTextFile(
    new URL("./platform_controls_routes.ts", import.meta.url),
  );
  assertStringIncludes(route, "grantsPermission: false");
  assertStringIncludes(route, "grantsEntitlement: false");
});
