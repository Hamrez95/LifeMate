import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  classifyWomenDailyLogWrite,
  mapRichDailyLog,
} from "./women_calendar_rich_period.ts";

Deno.test("rich period daily log exposes canonical structured observations", () => {
  const mapped = mapRichDailyLog({
    id: "11111111-1111-4111-8111-111111111111",
    logged_on: "2026-08-30",
    mood: "Neutral",
    energy_level: 3,
    pain_level: 0,
    pain_recorded: false,
    symptoms: ["cramps", "bloating"],
    symptom_observations: [
      { id: "cramps", severity: null },
      { id: "bloating", severity: 2 },
    ],
    symptom_schema_version: 1,
    private_notes: "یادداشت خصوصی",
    share_summary_with_companion: false,
    period_flow: "heavy",
    blood_appearance: "dark_red",
    blood_texture: "thick",
    period_observation_schema_version: 1,
    version: 2,
    created_at_utc: "2026-08-30T10:00:00.000Z",
    updated_at_utc: "2026-08-30T11:00:00.000Z",
  });

  assertEquals(mapped.periodFlow, "heavy");
  assertEquals(mapped.bloodAppearance, "dark_red");
  assertEquals(mapped.bloodTexture, "thick");
  assertEquals(mapped.schemaVersion, 1);
  assertEquals(mapped.painLevel, null);
  assertEquals(mapped.symptoms, ["cramps", "bloating"]);
  assertEquals(mapped.symptomObservations, [
    { id: "cramps", severity: null },
    { id: "bloating", severity: 2 },
  ]);
  assertEquals(mapped.symptomSchemaVersion, 1);
  assertEquals(mapped.privateNotes, "یادداشت خصوصی");
  assertEquals(mapped.shareSummaryWithCompanion, false);
});

Deno.test("legacy daily log remains compatible and pain stays visible", () => {
  const mapped = mapRichDailyLog({
    id: "22222222-2222-4222-8222-222222222222",
    logged_on: "2026-08-29",
    mood: "Good",
    energy_level: 4,
    pain_level: 2,
    pain_recorded: true,
    symptoms: ["Cramps"],
    symptom_observations: null,
    symptom_schema_version: 1,
    private_notes: null,
    share_summary_with_companion: true,
    period_flow: null,
    blood_appearance: null,
    blood_texture: null,
    period_observation_schema_version: 1,
    version: 3,
    created_at_utc: "2026-08-29T10:00:00.000Z",
    updated_at_utc: "2026-08-29T10:30:00.000Z",
  });

  assertEquals(mapped.painLevel, 2);
  assertEquals(mapped.symptoms, ["cramps"]);
  assertEquals(mapped.symptomObservations, [{ id: "cramps", severity: null }]);
  assertEquals(mapped.periodFlow, null);
  assertEquals(mapped.bloodAppearance, null);
  assertEquals(mapped.bloodTexture, null);
});


Deno.test("owner check-in routing wins over overlapping pain/symptom fields", () => {
  assertEquals(
    classifyWomenDailyLogWrite({
      mood: "low",
      energyLevel: 2,
      painLevel: 3,
      symptoms: ["cramps"],
      privateNotes: "owner only",
    }),
    "owner_check_in",
  );
  assertEquals(
    classifyWomenDailyLogWrite({
      periodFlow: "medium",
      painLevel: 2,
      symptoms: ["cramps"],
    }),
    "rich_period",
  );
});

Deno.test("mixed check-in and rich-only fields fail closed", () => {
  assertThrows(
    () => classifyWomenDailyLogWrite({
      mood: "good",
      energyLevel: 4,
      periodFlow: "light",
    }),
    Error,
    "Daily check-in and rich period-only fields must be saved separately.",
  );
});
