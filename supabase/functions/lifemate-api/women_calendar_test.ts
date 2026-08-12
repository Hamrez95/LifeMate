import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  calculateWomenCalendarEstimate,
  calculateWomenCalendarEstimateFromEpisodes,
} from "./women_calendar.ts";

Deno.test("women calendar estimate is deterministic without fertility claims", () => {
  const estimate = calculateWomenCalendarEstimate(
    "2026-08-01",
    28,
    5,
    new Date("2026-08-04T15:00:00Z"),
  );
  assertEquals(estimate.cycleDay, 4);
  assertEquals(estimate.estimatedBleeding, true);
  assertEquals(estimate.phase, "period");
  assertEquals(estimate.nextPeriodStart, "2026-08-29");
  assertEquals(estimate.daysUntilNextPeriod, 25);
  assertEquals(estimate.algorithmVersion, "calendar-estimate-v1");
});

Deno.test("women calendar estimate marks the pre-period window as an estimate", () => {
  const estimate = calculateWomenCalendarEstimate(
    "2026-08-01",
    28,
    5,
    new Date("2026-08-26T00:00:00Z"),
  );
  assertEquals(estimate.cycleDay, 26);
  assertEquals(estimate.phase, "pre_period");
  assertEquals(estimate.daysUntilNextPeriod, 3);
});

Deno.test("cycle history with insufficient data suppresses fertility timing", () => {
  const estimate = calculateWomenCalendarEstimateFromEpisodes(
    "2026-08-01",
    28,
    5,
    ["2026-07-04", "2026-08-01"],
    new Date("2026-08-14T00:00:00Z"),
  );
  assertEquals(estimate.confidence, "low");
  assertEquals(estimate.cyclePattern, "insufficient_data");
  assertEquals(estimate.fertilityEstimateReliable, false);
  assertEquals(
    ["fertile", "ovulation"].includes(estimate.detailedPhase),
    false,
  );
});

Deno.test("cycle history enables fertility only for stable repeated intervals", () => {
  const estimate = calculateWomenCalendarEstimateFromEpisodes(
    "2026-08-01",
    28,
    5,
    ["2026-05-09", "2026-06-06", "2026-07-04", "2026-08-01"],
    new Date("2026-08-14T00:00:00Z"),
  );
  assertEquals(estimate.cyclePattern, "regular");
  assertEquals(estimate.confidence, "high");
  assertEquals(estimate.fertilityEstimateReliable, true);
});

Deno.test("variable cycle history suppresses fertility timing", () => {
  const estimate = calculateWomenCalendarEstimateFromEpisodes(
    "2026-08-01",
    28,
    5,
    ["2026-05-01", "2026-05-25", "2026-07-04", "2026-08-01"],
    new Date("2026-08-14T00:00:00Z"),
  );
  assertEquals(estimate.cyclePattern, "variable");
  assertEquals(estimate.confidence, "low");
  assertEquals(estimate.fertilityEstimateReliable, false);
  assertEquals(
    ["fertile", "ovulation"].includes(estimate.detailedPhase),
    false,
  );
});
