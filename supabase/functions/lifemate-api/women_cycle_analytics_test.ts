import { assertEquals } from "jsr:@std/assert@1";
import { calculateWomenCycleAnalytics } from "./women_cycle_analytics.ts";

Deno.test("analytics returns honest empty state with no data", () => {
  const result = calculateWomenCycleAnalytics([], []);
  assertEquals(result.evidenceState, "none");
  assertEquals(result.cycleLength, {
    average: null,
    min: null,
    max: null,
    sampleSize: 0,
  });
  assertEquals(result.recordedFactsOnly, true);
});

Deno.test("one cycle remains learning and never fabricates average cycle length", () => {
  const result = calculateWomenCycleAnalytics([
    { startedOn: "2026-08-01", endedOn: "2026-08-05" },
  ], []);
  assertEquals(result.evidenceState, "learning");
  assertEquals(result.cycleLength.average, null);
  assertEquals(result.periodDuration.average, 5);
});

Deno.test("multiple cycles calculate descriptive average range and variation", () => {
  const result = calculateWomenCycleAnalytics([
    { startedOn: "2026-05-09", endedOn: "2026-05-13" },
    { startedOn: "2026-06-06", endedOn: "2026-06-10" },
    { startedOn: "2026-07-04", endedOn: "2026-07-09" },
    { startedOn: "2026-08-01", endedOn: "2026-08-05" },
  ], []);
  assertEquals(result.evidenceState, "ready");
  assertEquals(result.cycleLength, {
    average: 28,
    min: 28,
    max: 28,
    sampleSize: 3,
  });
  assertEquals(result.periodDuration, {
    average: 5.3,
    min: 5,
    max: 6,
    sampleSize: 4,
  });
  assertEquals(result.regularity, "stable");
});

Deno.test("extreme edited/outlier interval is excluded from descriptive cycle metrics", () => {
  const result = calculateWomenCycleAnalytics([
    { startedOn: "2026-03-01", endedOn: "2026-03-05" },
    { startedOn: "2026-03-29", endedOn: "2026-04-02" },
    { startedOn: "2026-04-26", endedOn: "2026-04-30" },
    { startedOn: "2026-06-20", endedOn: "2026-06-24" },
    { startedOn: "2026-07-18", endedOn: "2026-07-22" },
  ], []);
  assertEquals(result.cycleLength.average, 28);
  assertEquals(result.cycleLength.max, 28);
});

Deno.test("recurring symptom requires at least two recorded days and supports legacy values", () => {
  const result = calculateWomenCycleAnalytics([], [
    { loggedOn: "2026-08-01", painLevel: 2, symptoms: ["Headache"] },
    { loggedOn: "2026-08-02", painLevel: 3, symptoms: ["Headache", "Cramps"] },
    { loggedOn: "2026-08-03", painLevel: 1, symptoms: ["Cramps"] },
  ]);
  assertEquals(result.recurringSymptoms, [
    { id: "cramps", occurrences: 2 },
    { id: "headache", occurrences: 2 },
  ]);
  assertEquals(result.pain, {
    average: 2,
    min: 1,
    max: 3,
    sampleSize: 3,
  });
});

Deno.test("flow and blood observations are aggregated from recorded canonical values", () => {
  const result = calculateWomenCycleAnalytics([], [
    {
      loggedOn: "2026-08-01",
      painLevel: 1,
      symptoms: [],
      periodFlow: "heavy",
      bloodAppearance: "dark_red",
      bloodTexture: "thick",
    },
    {
      loggedOn: "2026-08-02",
      painLevel: 2,
      symptoms: [],
      periodFlow: "heavy",
      bloodAppearance: "red",
      bloodTexture: "usual",
    },
  ]);
  assertEquals(result.flowDistribution, { heavy: 2 });
  assertEquals(result.bloodAppearanceDistribution, { dark_red: 1, red: 1 });
  assertEquals(result.bloodTextureDistribution, { thick: 1, usual: 1 });
});
