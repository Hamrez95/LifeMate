import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  assertPortableExportSize,
  portableExportMaximumBytes,
  portableRow,
} from "./data_export.ts";
import { ApiError } from "./validation.ts";

Deno.test("portable export converts database field names without changing values", () => {
  const projected = portableRow({
    created_at_utc: "2026-08-14T00:00:00Z",
    patient_reminder_minutes_before: 30,
    provenance_restricted: true,
  });

  assertEquals(projected, {
    createdAtUtc: "2026-08-14T00:00:00Z",
    patientReminderMinutesBefore: 30,
    provenanceRestricted: true,
  });
});

Deno.test("portable export fails closed instead of silently truncating oversized payloads", () => {
  const error = assertThrows(
    () =>
      assertPortableExportSize({
        oversized: "x".repeat(portableExportMaximumBytes),
      }),
    ApiError,
  ) as ApiError;
  assertEquals(error.status, 413);
  assertEquals(error.code, "data_export_too_large");
});
