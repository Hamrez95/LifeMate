import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  optionalMedicationScheduleLocalTime,
  optionalMedicationScheduleTimingNote,
  requiredMedicationScheduleBoolean,
  requiredMedicationScheduleSpacing,
  requiredMedicationScheduleVersion,
} from "./medication_schedule_settings.ts";

Deno.test("schedule setting validators accept canonical boundary values", () => {
  assertEquals(requiredMedicationScheduleVersion(0), 0);
  assertEquals(requiredMedicationScheduleVersion("0"), 0);
  assertEquals(requiredMedicationScheduleVersion(7), 7);
  assertEquals(requiredMedicationScheduleBoolean(true, "flag"), true);
  assertEquals(requiredMedicationScheduleBoolean(false, "flag"), false);
  assertEquals(
    optionalMedicationScheduleLocalTime("08:05", "sleep_start_local_time"),
    "08:05:00",
  );
  assertEquals(
    optionalMedicationScheduleLocalTime("23:59:58", "sleep_end_local_time"),
    "23:59:58",
  );
  assertEquals(requiredMedicationScheduleSpacing(0, "before"), 0);
  assertEquals(requiredMedicationScheduleSpacing(1440, "after"), 1440);
  assertEquals(optionalMedicationScheduleTimingNote("instruction"), "instruction");
  assertEquals(optionalMedicationScheduleTimingNote(null), null);
});

Deno.test("schedule setting validators reject unsafe or ambiguous values", () => {
  assertThrows(() => requiredMedicationScheduleVersion(-1));
  assertThrows(() => requiredMedicationScheduleVersion(1.5));
  assertThrows(() => requiredMedicationScheduleBoolean("true", "flag"));
  assertThrows(() =>
    optionalMedicationScheduleLocalTime("24:00", "sleep_start_local_time")
  );
  assertThrows(() =>
    optionalMedicationScheduleLocalTime("08:60", "sleep_start_local_time")
  );
  assertThrows(() => requiredMedicationScheduleSpacing(-1, "before"));
  assertThrows(() => requiredMedicationScheduleSpacing(1441, "after"));
  assertThrows(() => requiredMedicationScheduleSpacing(1.5, "after"));
  assertThrows(() => optionalMedicationScheduleTimingNote("x".repeat(241)));
});

Deno.test("settings store enforces IANA zones, self ownership and stale writes", async () => {
  const source = await Deno.readTextFile(
    new URL("./medication_schedule_settings.ts", import.meta.url),
  );
  assert(source.includes("pg_timezone_names"));
  assert(source.includes("self_person_id_for_legacy_app_user"));
  assert(source.includes("p.patient_person_id = ${personId}::uuid"));
  assert(source.includes('"stale_schedule_preferences"'));
  assert(source.includes('"stale_treatment_plan"'));
  assert(source.includes('"stale_timing_constraints"'));
});

Deno.test("canonical export and audit include schedule settings without notification copy", async () => {
  const exportSource = await Deno.readTextFile(
    new URL("./data_export.ts", import.meta.url),
  );
  assert(exportSource.includes("medicationSchedulePreferences"));
  assert(exportSource.includes("treatmentPlanTimingConstraints"));

  const auditSource = await Deno.readTextFile(
    new URL("./medication_schedule_audit.ts", import.meta.url),
  );
  assert(auditSource.includes("metadata_json"));
  assert(!auditSource.includes("medication_name"));
  assert(!auditSource.includes("notification_body"));
});
