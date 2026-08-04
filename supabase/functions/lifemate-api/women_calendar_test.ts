import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { calculateWomenCalendarEstimate } from "./women_calendar.ts";

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
