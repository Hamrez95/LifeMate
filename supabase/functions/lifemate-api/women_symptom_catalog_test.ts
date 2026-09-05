import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  canonicalizeLegacySymptoms,
  mergeLegacySymptomsIntoObservations,
  normalizeStoredWomenSymptomObservations,
  normalizeWomenSymptomObservations,
  projectCanonicalSymptomsToLegacyStorage,
  womenSymptomCatalogVersion,
} from "./women_symptom_catalog.ts";

Deno.test("canonical symptom catalog maps historical stored values", () => {
  assertEquals(
    canonicalizeLegacySymptoms([
      "Cramps",
      "BackPain",
      "BreastTenderness",
      "SleepChange",
    ]),
    ["cramps", "lower_back_pain", "breast_tenderness", "sleep_changes"],
  );
  assertEquals(womenSymptomCatalogVersion, 1);
});

Deno.test("canonical symptoms preserve the legacy constrained storage shape", () => {
  assertEquals(
    projectCanonicalSymptomsToLegacyStorage([
      "cramps",
      "fatigue",
      "lower_back_pain",
      "sleep_changes",
      "no_symptom",
    ]),
    ["Cramps", "Fatigue", "BackPain", "SleepChange", "NoSymptom"],
  );
  assertEquals(
    projectCanonicalSymptomsToLegacyStorage([
      "migraine",
      "nausea",
      "mood_changes",
      "other",
    ]),
    [],
  );
});

Deno.test("canonical symptom observations support multiple independent symptoms", () => {
  assertEquals(
    normalizeWomenSymptomObservations([
      { id: "cramps", severity: 3 },
      { id: "nausea" },
      { id: "mood-changes", severity: 2 },
    ]),
    [
      { id: "cramps", severity: 3 },
      { id: "nausea", severity: null },
      { id: "mood_changes", severity: 2 },
    ],
  );
});

Deno.test("no_symptom cannot be combined with sensitive observations", () => {
  assertThrows(() =>
    normalizeWomenSymptomObservations([
      { id: "no_symptom" },
      { id: "cramps", severity: 1 },
    ])
  );
});

Deno.test("invalid symptom ids and severities fail closed", () => {
  assertThrows(() => normalizeWomenSymptomObservations([{ id: "diagnosis" }]));
  assertThrows(() =>
    normalizeWomenSymptomObservations([{ id: "headache", severity: 9 }])
  );
});

Deno.test("structured symptoms win, legacy remains read-compatible", () => {
  assertEquals(
    mergeLegacySymptomsIntoObservations(["Cramps", "Fatigue"], []),
    [
      { id: "cramps", severity: null },
      { id: "fatigue", severity: null },
    ],
  );
  assertEquals(
    mergeLegacySymptomsIntoObservations(
      ["Cramps"],
      [{ id: "migraine", severity: 4 }],
    ),
    [{ id: "migraine", severity: 4 }],
  );
});

Deno.test("stored mapping ignores malformed future/unknown values safely", () => {
  assertEquals(
    normalizeStoredWomenSymptomObservations([
      { id: "headache", severity: 2 },
      { id: "future_unknown", severity: 4 },
      { id: "fatigue", severity: 99 },
    ]),
    [
      { id: "headache", severity: 2 },
      { id: "fatigue", severity: null },
    ],
  );
});
