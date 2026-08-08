import { assertEquals } from "jsr:@std/assert@1.0.14";
import { generateCareEventOccurrenceDates } from "./care_events.ts";

Deno.test("appointment every six months expands deterministically", () => {
  assertEquals(
    generateCareEventOccurrenceDates(
      "2026-08-17",
      {
        enabled: true,
        unit: "month",
        interval: 6,
        weekdays: [],
        endDate: null,
      },
      "2026-08-01",
      "2027-08-31",
    ),
    ["2026-08-17", "2027-02-17", "2027-08-17"],
  );
});

Deno.test("month end recurrence clamps without duplicate dates", () => {
  const dates = generateCareEventOccurrenceDates(
    "2026-01-31",
    { enabled: true, unit: "month", interval: 1, weekdays: [], endDate: null },
    "2026-01-01",
    "2026-04-30",
  );
  assertEquals(dates, ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]);
  assertEquals(new Set(dates).size, dates.length);
});

Deno.test("weekly recurrence uses selected weekdays and interval", () => {
  const dates = generateCareEventOccurrenceDates(
    "2026-08-03",
    {
      enabled: true,
      unit: "week",
      interval: 2,
      weekdays: [1, 3],
      endDate: "2026-08-31",
    },
    "2026-08-01",
    "2026-08-31",
  );
  assertEquals(dates, [
    "2026-08-03",
    "2026-08-05",
    "2026-08-17",
    "2026-08-19",
    "2026-08-31",
  ]);
  assertEquals(new Set(dates).size, dates.length);
});
