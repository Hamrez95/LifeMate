import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ApiError } from "./validation.ts";
import { normalizeHealthObservationInput } from "./health_observations.ts";

const now = new Date("2026-08-10T08:30:00Z");
const requestId = "123e4567-e89b-42d3-a456-426614174000";

Deno.test("health observation normalizes a manual weight record", () => {
  const value = normalizeHealthObservationInput(
    {
      clientRequestId: requestId,
      observationType: "weight",
      valuePrimary: 78.4,
      observedAtUtc: "2026-08-10T08:00:00Z",
      observedLocalDate: "2026-08-10",
      timeZone: "Asia/Tehran",
    },
    now,
  );
  assertEquals(value.observationType, "weight");
  assertEquals(value.valuePrimary, 78.4);
  assertEquals(value.valueSecondary, null);
  assertEquals(value.unitPrimary, "kg");
});

Deno.test("health observation ignores client application provenance claims", () => {
  const value = normalizeHealthObservationInput(
    {
      clientRequestId: requestId,
      sourceApplicationCode: "caremate",
      observationType: "heart_rate",
      valuePrimary: 72,
      observedAtUtc: "2026-08-10T08:00:00Z",
      observedLocalDate: "2026-08-10",
      timeZone: "Asia/Tehran",
    },
    now,
  );
  assertEquals(value.observationType, "heart_rate");
  assertEquals("sourceApplicationCode" in value, false);
});

Deno.test("health observation accepts systolic and diastolic pressure", () => {
  const value = normalizeHealthObservationInput(
    {
      clientRequestId: requestId,
      observationType: "blood_pressure",
      valuePrimary: 118,
      valueSecondary: 76,
      observedAtUtc: "2026-08-10T08:00:00Z",
      observedLocalDate: "2026-08-10",
      timeZone: "Asia/Tehran",
    },
    now,
  );
  assertEquals(value.valuePrimary, 118);
  assertEquals(value.valueSecondary, 76);
  assertEquals(value.unitPrimary, "mmHg");
});

Deno.test("health note requires text and stores no numeric value", () => {
  const value = normalizeHealthObservationInput(
    {
      clientRequestId: requestId,
      observationType: "note",
      note: "بعد از پیاده‌روی احساس خوبی داشتم.",
      observedAtUtc: "2026-08-10T08:00:00Z",
      observedLocalDate: "2026-08-10",
      timeZone: "Asia/Tehran",
    },
    now,
  );
  assertEquals(value.note, "بعد از پیاده‌روی احساس خوبی داشتم.");
  assertEquals(value.valuePrimary, null);
});

Deno.test("health observation rejects physiologically impossible pressure ordering", () => {
  const error = assertThrows(
    () =>
      normalizeHealthObservationInput(
        {
          clientRequestId: requestId,
          observationType: "blood_pressure",
          valuePrimary: 70,
          valueSecondary: 90,
          observedAtUtc: "2026-08-10T08:00:00Z",
          observedLocalDate: "2026-08-10",
          timeZone: "Asia/Tehran",
        },
        now,
      ),
    ApiError,
  );
  assertEquals(error.code, "invalid_blood_pressure");
});

Deno.test("health observation rejects unsupported metric types", () => {
  const error = assertThrows(
    () =>
      normalizeHealthObservationInput(
        {
          clientRequestId: requestId,
          observationType: "health_score",
          valuePrimary: 90,
          observedAtUtc: "2026-08-10T08:00:00Z",
          observedLocalDate: "2026-08-10",
          timeZone: "Asia/Tehran",
        },
        now,
      ),
    ApiError,
  );
  assertEquals(error.code, "invalid_observationType");
});
