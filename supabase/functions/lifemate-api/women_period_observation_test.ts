import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  mapStoredPeriodObservation,
  normalizePeriodObservation,
  periodObservationSchemaVersion,
} from "./women_period_observation.ts";

Deno.test("period observation fields are independently optional", () => {
  assertEquals(normalizePeriodObservation({}), {
    periodFlow: null,
    bloodAppearance: null,
    bloodTexture: null,
    schemaVersion: periodObservationSchemaVersion,
  });
  assertEquals(normalizePeriodObservation({ periodFlow: "heavy" }), {
    periodFlow: "heavy",
    bloodAppearance: null,
    bloodTexture: null,
    schemaVersion: periodObservationSchemaVersion,
  });
});

Deno.test("period observation accepts canonical neutral values", () => {
  assertEquals(
    normalizePeriodObservation({
      periodFlow: "medium",
      bloodAppearance: "dark-red",
      bloodTexture: "clot-observed",
    }),
    {
      periodFlow: "medium",
      bloodAppearance: "dark_red",
      bloodTexture: "clot_observed",
      schemaVersion: 1,
    },
  );
});

Deno.test("period observation rejects diagnostic or arbitrary values", () => {
  assertThrows(() => normalizePeriodObservation({ periodFlow: "dangerous" }));
  assertThrows(() =>
    normalizePeriodObservation({ bloodAppearance: "abnormal" })
  );
  assertThrows(() => normalizePeriodObservation({ bloodTexture: "disease" }));
});

Deno.test("stored observation mapping is versioned and fail-safe", () => {
  assertEquals(
    mapStoredPeriodObservation({
      period_flow: "light",
      blood_appearance: "brown",
      blood_texture: "usual",
      period_observation_schema_version: 1,
    }),
    {
      periodFlow: "light",
      bloodAppearance: "brown",
      bloodTexture: "usual",
      schemaVersion: 1,
    },
  );
  assertEquals(
    mapStoredPeriodObservation({ period_flow: "legacy_unknown" }),
    {
      periodFlow: null,
      bloodAppearance: null,
      bloodTexture: null,
      schemaVersion: 1,
    },
  );
});
