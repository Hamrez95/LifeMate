import { assertEquals } from "jsr:@std/assert@1";
import { guidanceAllowed } from "./person_women_calendar_caregiver.ts";

const scopes = (overrides: Record<string, boolean> = {}) => ({
  viewPeriodTiming: true,
  viewPhaseSummary: true,
  viewSharedWellbeing: false,
  receiveMoodSupportNotifications: false,
  receivePhaseNotifications: true,
  viewFertilityEstimate: false,
  receiveFertilityNotifications: false,
  viewCalendarDetail: false,
  ...overrides,
});

Deno.test("phase notification receipt requires receive scope at write time", () => {
  assertEquals(
    guidanceAllowed(
      "notify.phase.luteal.2026-08-28",
      "phase",
      scopes({ receivePhaseNotifications: false }),
    ),
    false,
  );
});

Deno.test("period start notification also requires timing scope", () => {
  assertEquals(
    guidanceAllowed(
      "notify.phase.period_start.2026-08-28",
      "phase",
      scopes({ viewPeriodTiming: false }),
    ),
    false,
  );
});

Deno.test("ordinary in-app phase guidance does not borrow notification scope", () => {
  assertEquals(
    guidanceAllowed(
      "phase.be_present",
      "phase",
      scopes({ receivePhaseNotifications: false }),
    ),
    true,
  );
});
