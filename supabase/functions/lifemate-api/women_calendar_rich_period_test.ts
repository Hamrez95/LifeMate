import { assertEquals } from "jsr:@std/assert@1";
import { mapRichDailyLog } from "./women_calendar_rich_period.ts";

Deno.test("rich period daily log exposes canonical structured observations", () => {
  const mapped = mapRichDailyLog({
    id: "11111111-1111-4111-8111-111111111111",
    logged_on: "2026-08-30",
    mood: "Neutral",
    energy_level: 3,
    pain_level: 0,
    pain_recorded: false,
    symptoms: [],
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
  assertEquals(mapped.periodFlow, null);
  assertEquals(mapped.bloodAppearance, null);
  assertEquals(mapped.bloodTexture, null);
});
