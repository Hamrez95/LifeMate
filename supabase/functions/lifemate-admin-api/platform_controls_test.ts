import { evaluatePlatformControl } from "./platform_controls.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

const definition = { key: "beta.new_home", kind: "FeatureFlag" as const, valueType: "Boolean" as const, defaultValue: false, failClosed: true, version: 1 };

Deno.test("platform control defaults fail closed", async () => {
  const result = await evaluatePlatformControl(definition, [], { subjectKey: "account-1" });
  assertEquals(result.value, false);
  assertEquals(result.source, "default");
});

Deno.test("higher-priority product rule wins deterministically", async () => {
  const rules = [
    { id: "b", priority: 200, targetType: "Global" as const, targetKey: null, rolloutBasisPoints: null, value: false, startsAtUtc: null, endsAtUtc: null, version: 1 },
    { id: "a", priority: 10, targetType: "Product" as const, targetKey: "wellmate-caremate", rolloutBasisPoints: null, value: true, startsAtUtc: null, endsAtUtc: null, version: 1 },
  ];
  const result = await evaluatePlatformControl(definition, rules, { subjectKey: "account-1", productCode: "wellmate-caremate" });
  assertEquals(result.value, true);
  assertEquals(result.ruleId, "a");
});

Deno.test("percentage assignment is stable for the same opaque subject", async () => {
  const rules = [{ id: "p", priority: 1, targetType: "Percentage" as const, targetKey: "rollout", rolloutBasisPoints: 5000, value: true, startsAtUtc: null, endsAtUtc: null, version: 1 }];
  const first = await evaluatePlatformControl(definition, rules, { subjectKey: "8e1d7d0c-opaque" });
  const second = await evaluatePlatformControl(definition, rules, { subjectKey: "8e1d7d0c-opaque" });
  assertEquals(first, second);
});
