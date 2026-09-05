import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  assertNotificationMetadata,
  guidanceAllowed,
  presentCycleEstimate,
  presentFertilityEstimate,
} from "./person_women_calendar_caregiver.ts";

const scopes = (overrides: Record<string, boolean> = {}) => ({
  viewPeriodTiming: true,
  viewPhaseSummary: true,
  viewSharedWellbeing: true,
  receiveMoodSupportNotifications: true,
  receivePhaseNotifications: true,
  viewFertilityEstimate: false,
  receiveFertilityNotifications: false,
  viewCalendarDetail: false,
  ...overrides,
});

const rawEstimate = {
  cycleStart: "2026-08-15",
  cycleDay: 14,
  cycleLength: 28,
  periodLength: 5,
  estimatedBleeding: false,
  phase: "cycle",
  detailedPhase: "ovulation",
  ovulationDay: 14,
  fertileWindowStartDay: 11,
  fertileWindowEndDay: 16,
  pmsStartDay: 24,
  nextPeriodStart: "2026-09-12",
  daysUntilNextPeriod: 15,
  algorithmVersion: "calendar-estimate-v1",
  confidence: "high",
  cyclePattern: "regular",
  fertilityEstimateReliable: true,
};

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

Deno.test("mood notification receipt requires its independent receive scope", () => {
  assertEquals(
    guidanceAllowed(
      "notify.mood.check_in.2026-08-28",
      "mood",
      scopes({ receiveMoodSupportNotifications: false }),
    ),
    false,
  );
});

Deno.test("mood notification also requires shared wellbeing scope", () => {
  assertEquals(
    guidanceAllowed(
      "notify.mood.energy.2026-08-28",
      "mood",
      scopes({ viewSharedWellbeing: false }),
    ),
    false,
  );
});

Deno.test("ordinary in-app mood guidance does not borrow notification consent", () => {
  assertEquals(
    guidanceAllowed(
      "mood.gentle_check_in",
      "mood",
      scopes({ receiveMoodSupportNotifications: false }),
    ),
    true,
  );
});

Deno.test("fertility notification requires both independent fertility scopes", () => {
  const id = "notify.fertility.window.2026-08-25";
  assertEquals(
    guidanceAllowed(
      id,
      "fertility",
      scopes({
        viewFertilityEstimate: false,
        receiveFertilityNotifications: true,
      }),
    ),
    false,
  );
  assertEquals(
    guidanceAllowed(
      id,
      "fertility",
      scopes({
        viewFertilityEstimate: true,
        receiveFertilityNotifications: false,
      }),
    ),
    false,
  );
  assertEquals(
    guidanceAllowed(
      id,
      "fertility",
      scopes({
        viewFertilityEstimate: true,
        receiveFertilityNotifications: true,
        viewPhaseSummary: false,
        receivePhaseNotifications: false,
      }),
    ),
    true,
  );
});

Deno.test("fertility view category does not borrow ordinary phase scope", () => {
  assertEquals(
    guidanceAllowed(
      "fertility.explanation",
      "fertility",
      scopes({ viewFertilityEstimate: false, viewPhaseSummary: true }),
    ),
    false,
  );
});

Deno.test("fertility-only projection does not expose period timing or phase", () => {
  const privacy = scopes({
    viewPeriodTiming: false,
    viewPhaseSummary: false,
    viewSharedWellbeing: false,
    receiveMoodSupportNotifications: false,
    receivePhaseNotifications: false,
    viewFertilityEstimate: true,
    receiveFertilityNotifications: false,
    viewCalendarDetail: false,
  });
  assertEquals(presentCycleEstimate(rawEstimate, privacy), null);
  assertEquals(
    presentFertilityEstimate(rawEstimate, privacy),
    {
      state: "inside_estimated_window",
      estimatedWindowStartOn: "2026-08-25",
      estimatedWindowEndOn: "2026-08-30",
      estimatedOvulationOn: "2026-08-28",
      fertilityEstimateReliable: true,
      confidence: "high",
      cyclePattern: "regular",
      algorithmVersion: "calendar-estimate-v1",
    },
  );
});

Deno.test("phase-only projection hides raw fertile and ovulation phase values", () => {
  const privacy = scopes({
    viewPeriodTiming: false,
    viewPhaseSummary: true,
    viewFertilityEstimate: false,
    viewCalendarDetail: false,
  });
  const result = presentCycleEstimate(rawEstimate, privacy);
  assertEquals(result?.detailedPhase, "follicular");
  assertEquals("ovulationDay" in (result ?? {}), false);
  assertEquals("fertileWindowStartDay" in (result ?? {}), false);
});

Deno.test("irregular fertility projection returns unknown without estimated dates", () => {
  const privacy = scopes({ viewFertilityEstimate: true });
  const result = presentFertilityEstimate(
    {
      ...rawEstimate,
      cyclePattern: "variable",
      fertilityEstimateReliable: false,
    },
    privacy,
  );
  assertEquals(result?.state, "unavailable");
  assertEquals(result?.estimatedWindowStartOn, null);
  assertEquals(result?.estimatedOvulationOn, null);
});

Deno.test("mood notification metadata cannot masquerade as another category", () => {
  assertThrows(() =>
    assertNotificationMetadata(
      "notify.mood.check_in.2026-08-28",
      "companion-mood-notifications-v1",
      "general",
    )
  );
});

Deno.test("mood notification requires the canonical content version", () => {
  assertThrows(() =>
    assertNotificationMetadata(
      "notify.mood.energy.2026-08-28",
      "companion-mood-notifications-v0",
      "mood",
    )
  );
});

Deno.test("canonical mood notification metadata is accepted", () => {
  assertNotificationMetadata(
    "notify.mood.check_in.2026-08-28",
    "companion-mood-notifications-v1",
    "mood",
  );
});

Deno.test("fertility notification metadata is isolated from phase metadata", () => {
  assertThrows(() =>
    assertNotificationMetadata(
      "notify.fertility.window.2026-08-25",
      "companion-phase-notifications-v1",
      "phase",
    )
  );
  assertNotificationMetadata(
    "notify.fertility.window.2026-08-25",
    "companion-fertility-notifications-v1",
    "fertility",
  );
});

Deno.test("unknown notification namespaces fail closed", () => {
  assertThrows(() =>
    assertNotificationMetadata(
      "notify.unknown.sensitive.2026-08-28",
      "unknown-v1",
      "general",
    )
  );
});
