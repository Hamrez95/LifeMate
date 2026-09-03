import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  deriveGestationalAge,
  PregnancyDatingError,
} from "./pregnancy_dating.ts";

Deno.test("LMP dating derives deterministic week/day", () => {
  const result = deriveGestationalAge({
    method: "lmp",
    lmpDate: "2026-01-01",
    estimatedDueDate: null,
    referenceDate: null,
    gestationalAgeAtReferenceDays: null,
  }, "2026-01-15");

  assertEquals(result, {
    totalDays: 14,
    week: 2,
    day: 0,
    basis: "lmp",
  });
});

Deno.test("EDD dating reaches exactly 40w0d on due date", () => {
  const result = deriveGestationalAge({
    method: "edd",
    lmpDate: null,
    estimatedDueDate: "2026-10-08",
    referenceDate: null,
    gestationalAgeAtReferenceDays: null,
  }, "2026-10-08");

  assertEquals(result, {
    totalDays: 280,
    week: 40,
    day: 0,
    basis: "edd",
  });
});

Deno.test("clinician dating uses reference gestational age without inventing LMP", () => {
  const result = deriveGestationalAge({
    method: "clinician_ultrasound",
    lmpDate: null,
    estimatedDueDate: null,
    referenceDate: "2026-06-01",
    gestationalAgeAtReferenceDays: 84,
  }, "2026-06-08");

  assertEquals(result, {
    totalDays: 91,
    week: 13,
    day: 0,
    basis: "reference",
  });
});

Deno.test("manual correction prefers clinician reference over stale EDD/LMP", () => {
  const result = deriveGestationalAge({
    method: "manual_correction",
    lmpDate: "2026-01-01",
    estimatedDueDate: "2026-10-08",
    referenceDate: "2026-06-01",
    gestationalAgeAtReferenceDays: 100,
  }, "2026-06-02");

  assertEquals(result?.basis, "reference");
  assertEquals(result?.totalDays, 101);
});

Deno.test("partial unknown dating remains unknown", () => {
  assertEquals(deriveGestationalAge({
    method: null,
    lmpDate: null,
    estimatedDueDate: null,
    referenceDate: null,
    gestationalAgeAtReferenceDays: null,
  }, "2026-09-03"), null);
});

Deno.test("as-of date before known gestational basis returns unknown", () => {
  assertEquals(deriveGestationalAge({
    method: "lmp",
    lmpDate: "2026-09-10",
    estimatedDueDate: null,
    referenceDate: null,
    gestationalAgeAtReferenceDays: null,
  }, "2026-09-03"), null);
});

Deno.test("invalid calendar dates fail closed", () => {
  assertThrows(
    () => deriveGestationalAge({
      method: "lmp",
      lmpDate: "2026-02-30",
      estimatedDueDate: null,
      referenceDate: null,
      gestationalAgeAtReferenceDays: null,
    }, "2026-09-03"),
    PregnancyDatingError,
    "lmp_date_invalid",
  );
});

Deno.test("clinician method requires complete reference pair", () => {
  assertThrows(
    () => deriveGestationalAge({
      method: "clinician_ultrasound",
      lmpDate: null,
      estimatedDueDate: null,
      referenceDate: "2026-06-01",
      gestationalAgeAtReferenceDays: null,
    }, "2026-09-03"),
    PregnancyDatingError,
    "clinician_reference_required",
  );
});

Deno.test("local date input makes timezone boundary an explicit caller contract", () => {
  const beforeLocalMidnight = deriveGestationalAge({
    method: "lmp",
    lmpDate: "2026-01-01",
    estimatedDueDate: null,
    referenceDate: null,
    gestationalAgeAtReferenceDays: null,
  }, "2026-01-07");
  const afterLocalMidnight = deriveGestationalAge({
    method: "lmp",
    lmpDate: "2026-01-01",
    estimatedDueDate: null,
    referenceDate: null,
    gestationalAgeAtReferenceDays: null,
  }, "2026-01-08");

  assertEquals(beforeLocalMidnight?.totalDays, 6);
  assertEquals(afterLocalMidnight?.totalDays, 7);
  assertEquals(afterLocalMidnight?.week, 1);
  assertEquals(afterLocalMidnight?.day, 0);
});
