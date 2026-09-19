import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  createPregnancyMeasurementObservation,
  normalizePregnancyMeasurementType,
} from "./pregnancy_measurements.ts";
import { ApiError } from "./validation.ts";

Deno.test("Cocoon pregnancy measurements reuse only approved canonical observation types", () => {
  assertEquals(normalizePregnancyMeasurementType(" weight "), "weight");
  assertEquals(
    normalizePregnancyMeasurementType("BLOOD_PRESSURE"),
    "blood_pressure",
  );
  assertEquals(
    normalizePregnancyMeasurementType("blood_glucose"),
    "blood_glucose",
  );
});

Deno.test("Cocoon pregnancy measurements reject unsupported observation expansion", () => {
  for (const unsupported of ["heart_rate", "note", "maternal_measurement"]) {
    const error = assertThrows(
      () => normalizePregnancyMeasurementType(unsupported),
      ApiError,
    );
    assertEquals(error.status, 400);
    assertEquals(error.code, "pregnancy_measurement_type_invalid");
  }
});

Deno.test("Cocoon pregnancy measurement creation fixes trusted source provenance", async () => {
  let capturedUserId = "";
  let capturedBody: Record<string, unknown> = {};
  let capturedApplicationCode: string | undefined;

  const created = await createPregnancyMeasurementObservation(
    async (appUserId, body, trustedApplicationCode) => {
      capturedUserId = appUserId;
      capturedBody = body;
      capturedApplicationCode = trustedApplicationCode;
      return {
        id: "11111111-1111-4111-8111-111111111111",
        observationType: body.observationType,
        sourceApplicationCode: trustedApplicationCode,
      };
    },
    "22222222-2222-4222-8222-222222222222",
    {
      observationType: " BLOOD_PRESSURE ",
      valuePrimary: 120,
      valueSecondary: 80,
      sourceApplicationCode: "spoofed-client-app",
    },
  );

  assertEquals(capturedUserId, "22222222-2222-4222-8222-222222222222");
  assertEquals(capturedBody.observationType, "blood_pressure");
  assertEquals(capturedBody.sourceApplicationCode, "spoofed-client-app");
  assertEquals(capturedApplicationCode, "cocoonmate");
  assertEquals(created.sourceApplicationCode, "cocoonmate");
});
