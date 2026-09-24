import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { normalizePregnancyCalendarClassification } from "./pregnancy_calendar.ts";
import { ApiError } from "./validation.ts";

Deno.test("pregnancy calendar accepts only supported classifications", () => {
  assertEquals(normalizePregnancyCalendarClassification(" prenatal "), "prenatal");
  assertEquals(normalizePregnancyCalendarClassification("ULTRASOUND"), "ultrasound");
  assertEquals(normalizePregnancyCalendarClassification("lab_test"), "lab_test");
});

Deno.test("pregnancy calendar rejects an invented classification", () => {
  const error = assertThrows(
    () => normalizePregnancyCalendarClassification("milestone"),
    ApiError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "pregnancy_calendar_classification_invalid");
});
