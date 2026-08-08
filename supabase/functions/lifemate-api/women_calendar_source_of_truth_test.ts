import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { assertCanonicalWomenDailyLogPayload } from "./women_calendar.ts";

Deno.test("profile settings reject the legacy embedded daily check-in field", () => {
  const error = assertThrows(
    () =>
      assertCanonicalWomenDailyLogPayload({ dailyCheckIn: { mood: "good" } }),
  );
  assertEquals(
    (error as { code?: string }).code,
    "women_calendar_daily_log_endpoint_required",
  );
});

Deno.test("profile settings accept persistent configuration without daily state", () => {
  assertCanonicalWomenDailyLogPayload({
    enabled: true,
    cycleLength: 28,
    periodLength: 5,
    remindersEnabled: true,
  });
});
