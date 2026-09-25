import { assertStringIncludes } from "jsr:@std/assert";

Deno.test("manual entitlement schedule modes preserve canonical camel-case semantics", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827030400_manual_entitlement_schedule_normalization.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(migration, "when 'exactexpiry' then 'ExactExpiry'");
  assertStringIncludes(migration, "when 'adddays' then 'AddDays'");
  assertStringIncludes(migration, "when 'addmonths' then 'AddMonths'");
  assertStringIncludes(migration, "when 'immediate' then 'Immediate'");
  assertStringIncludes(migration, "security definer");
  assertStringIncludes(migration, "exact_expiry_required");
});
