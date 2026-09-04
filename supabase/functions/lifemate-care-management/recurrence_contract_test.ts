import { assertEquals, assertThrows } from "jsr:@std/assert";
import {
  normalizeCareRecurrence,
  normalizeCareRecurrenceStartTime,
  recurrencePublicValue,
} from "./recurrence_contract.ts";

const error = (_status: number, code: string, message: string) => {
  const value = new Error(message);
  value.name = code;
  return value;
};

Deno.test("care recurrence accepts every six hours with an exact end", () => {
  const rule = normalizeCareRecurrence({
    version: 2,
    enabled: true,
    unit: "hour",
    interval: 6,
    endAt: "2026-08-27T02:00:00",
    maxOccurrences: 4,
  }, error);
  assertEquals(rule, {
    version: 2,
    enabled: true,
    unit: "hour",
    interval: 6,
    weekdays: [],
    endAt: "2026-08-27T02:00:00",
    maxOccurrences: 4,
  });
  assertEquals(normalizeCareRecurrenceStartTime("08:00", error), "08:00");
});

Deno.test("date-only recurrence ends remain inclusive for calendar units", () => {
  const rule = normalizeCareRecurrence({
    enabled: true,
    unit: "month",
    interval: 1,
    endDate: "2026-10-31",
  }, error);
  assertEquals(rule?.endAt, "2026-10-31T23:59:59");
  assertEquals(recurrencePublicValue(rule).endDate, "2026-10-31");
});

Deno.test("weekly recurrence deduplicates and sorts ISO weekdays", () => {
  const rule = normalizeCareRecurrence({
    enabled: true,
    unit: "week",
    interval: 2,
    weekdays: [7, 1, 7, 3],
  }, error);
  assertEquals(rule?.weekdays, [1, 3, 7]);
});

Deno.test("care recurrence rejects invalid timestamp and non-week weekdays", () => {
  assertThrows(() =>
    normalizeCareRecurrence({
      enabled: true,
      unit: "hour",
      interval: 6,
      endAt: "2026-08-27T27:00:00",
    }, error)
  );
  assertThrows(() =>
    normalizeCareRecurrence({
      enabled: true,
      unit: "day",
      interval: 1,
      weekdays: [1],
    }, error)
  );
});
