import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  normalizePregnancyEnergy,
  normalizePregnancyFeeling,
  normalizePregnancyMood,
  normalizePregnancySymptomCode,
  normalizePregnancySymptomIntensity,
  requestedCatalogLocale,
  requiredCatalogVersion,
} from "./pregnancy_capture.ts";
import { ApiError } from "./validation.ts";

Deno.test("pregnancy check-in fields are bounded and normalized", () => {
  assertEquals(normalizePregnancyFeeling(" Comfortable "), "comfortable");
  assertEquals(normalizePregnancyEnergy("HIGH"), "high");
  const invalid = assertThrows(
    () => normalizePregnancyFeeling("diagnosed_depression"),
    ApiError,
  );
  assertEquals(invalid.code, "invalid_feeling");
});

Deno.test("pregnancy symptom capture accepts structured codes only", () => {
  assertEquals(
    normalizePregnancySymptomCode(" nausea.morning "),
    "nausea.morning",
  );
  assertEquals(normalizePregnancySymptomIntensity("STRONG"), "strong");
  const freeText = assertThrows(
    () => normalizePregnancySymptomCode("I feel very dizzy today!"),
    ApiError,
  );
  assertEquals(freeText.code, "invalid_symptomCode");
});

Deno.test("symptom catalog accepts only a reviewed version and supported locale", () => {
  assertEquals(
    requiredCatalogVersion(" pregnancy-symptoms-v2 "),
    "pregnancy-symptoms-v2",
  );
  assertEquals(
    requestedCatalogLocale(
      new Request("https://api.example.test/catalog?locale=fa"),
    ),
    "fa",
  );
  assertEquals(
    assertThrows(() => requiredCatalogVersion(""), ApiError).code,
    "pregnancy_symptom_catalog_version_invalid",
  );
  assertEquals(
    assertThrows(
      () =>
        requestedCatalogLocale(
          new Request("https://api.example.test/catalog?locale=fr"),
        ),
      ApiError,
    ).code,
    "pregnancy_symptom_catalog_locale_invalid",
  );
});

Deno.test("pregnancy mood capture remains a bounded non-diagnostic self-report", () => {
  assertEquals(normalizePregnancyMood("VERY_GOOD"), "very_good");
  const diagnosis = assertThrows(
    () => normalizePregnancyMood("major_depression"),
    ApiError,
  );
  assertEquals(diagnosis.code, "invalid_moodCode");
});
