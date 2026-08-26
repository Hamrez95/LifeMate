import {
  companionPrivacyScopeKeys,
  defaultCompanionPrivacyScopes,
} from "./women_companion_privacy.ts";

Deno.test("companion privacy defaults every sensitive scope to off", () => {
  const scopes = defaultCompanionPrivacyScopes();
  assertEquals(companionPrivacyScopeKeys.length, 8);
  assertEquals(new Set(companionPrivacyScopeKeys).size, 8);
  for (const key of companionPrivacyScopeKeys) assertEquals(scopes[key], false);
});

Deno.test("caregiver projection keeps private daily-log fields out of source", async () => {
  const source = await Deno.readTextFile(
    new URL("./person_women_calendar_caregiver.ts", import.meta.url),
  );
  const sharedProjection = source.slice(
    source.indexOf("const sharedLogs"),
    source.indexOf("const profile = profiles[0]"),
  );
  assert(!sharedProjection.includes("private_note"));
  assert(!sharedProjection.includes("pain_level"));
  assert(!sharedProjection.includes("symptoms"));
});

function assert(condition: unknown): asserts condition {
  if (!condition) throw new Error("Assertion failed");
}
function assertEquals(actual: unknown, expected: unknown) {
  if (actual !== expected) {
    throw new Error(`Expected ${String(expected)}, got ${String(actual)}`);
  }
}
