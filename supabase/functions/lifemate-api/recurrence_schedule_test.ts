import { assertEquals, assertThrows } from "jsr:@std/assert";
import {
  expandLocalRecurrence,
  normalizeRecurrenceRule,
} from "./recurrence_schedule.ts";

Deno.test("every six hours produces four occurrences across a normal full day", () => {
  const rule = normalizeRecurrenceRule({
    version: 2,
    enabled: true,
    unit: "hour",
    interval: 6,
  })!;
  assertEquals(
    expandLocalRecurrence(
      "2026-08-26T08:00:00",
      rule,
      "2026-08-26T00:00:00",
      "2026-08-27T07:59:59",
    ),
    [
      "2026-08-26T08:00:00",
      "2026-08-26T14:00:00",
      "2026-08-26T20:00:00",
      "2026-08-27T02:00:00",
    ],
  );
});

Deno.test("six month checkup preserves local clock and clamps month end", () => {
  const rule = normalizeRecurrenceRule({
    enabled: true,
    unit: "month",
    interval: 6,
  })!;
  assertEquals(
    expandLocalRecurrence(
      "2026-08-31T14:30:00",
      rule,
      "2026-08-01T00:00:00",
      "2027-09-01T00:00:00",
    ),
    [
      "2026-08-31T14:30:00",
      "2027-02-28T14:30:00",
      "2027-08-31T14:30:00",
    ],
  );
});

Deno.test("count bound applies to the whole hourly series", () => {
  const rule = normalizeRecurrenceRule({
    enabled: true,
    unit: "hour",
    interval: 6,
    maxOccurrences: 4,
  })!;
  assertEquals(
    expandLocalRecurrence(
      "2026-08-26T08:00:00",
      rule,
      "2026-08-26T18:00:00",
      "2026-08-30T00:00:00",
    ),
    ["2026-08-26T20:00:00", "2026-08-27T02:00:00"],
  );
});

Deno.test("weekly recurrence is anchored and deterministic", () => {
  const rule = normalizeRecurrenceRule({
    enabled: true,
    unit: "week",
    interval: 2,
    weekdays: [1, 3],
  })!;
  assertEquals(
    expandLocalRecurrence(
      "2026-08-03T09:15:00",
      rule,
      "2026-08-03T00:00:00",
      "2026-08-20T23:59:59",
    ),
    [
      "2026-08-03T09:15:00",
      "2026-08-05T09:15:00",
      "2026-08-17T09:15:00",
      "2026-08-19T09:15:00",
    ],
  );
});

Deno.test("dense recurrence fails bounded instead of materializing unbounded work", () => {
  const rule = normalizeRecurrenceRule({
    enabled: true,
    unit: "hour",
    interval: 1,
  })!;
  assertThrows(() =>
    expandLocalRecurrence(
      "2026-01-01T00:00:00",
      rule,
      "2026-01-01T00:00:00",
      "2026-03-01T00:00:00",
      100,
    )
  );
});

Deno.test("non-week recurrence rejects weekday filters", () => {
  assertThrows(() =>
    normalizeRecurrenceRule({
      enabled: true,
      unit: "hour",
      interval: 6,
      weekdays: [1],
    })
  );
});
