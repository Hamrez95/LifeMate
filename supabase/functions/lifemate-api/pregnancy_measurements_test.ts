import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  normalizePregnancyMeasurementType,
  pregnancyMeasurementInputSchema,
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


Deno.test("Cocoon pregnancy measurement input schema reuses canonical units without clinical thresholds", () => {
  assertEquals(pregnancyMeasurementInputSchema(), [
    {
      observationType: "weight",
      fields: [
        {
          wireField: "valuePrimary",
          semanticRole: "weight",
          unit: "kg",
        },
      ],
    },
    {
      observationType: "blood_pressure",
      fields: [
        {
          wireField: "valuePrimary",
          semanticRole: "systolic",
          unit: "mmHg",
        },
        {
          wireField: "valueSecondary",
          semanticRole: "diastolic",
          unit: "mmHg",
        },
      ],
    },
    {
      observationType: "blood_glucose",
      fields: [
        {
          wireField: "valuePrimary",
          semanticRole: "blood_glucose",
          unit: "mg/dL",
        },
      ],
    },
  ]);
});
