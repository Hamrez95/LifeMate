import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  isMinuteInsideSleepWindow,
  proposeExactSleepAwareAnchor,
  proposeFlexibleSleepAwareSequence,
} from "./medication_schedule_sleep_solver.ts";

Deno.test("cross-midnight sleep window is interpreted correctly", () => {
  const sleep = { startLocalTime: "23:00", endLocalTime: "07:00" };
  assertEquals(isMinuteInsideSleepWindow(23 * 60 + 30, sleep), true);
  assertEquals(isMinuteInsideSleepWindow(2 * 60, sleep), true);
  assertEquals(isMinuteInsideSleepWindow(12 * 60, sleep), false);
});

Deno.test("exact sleep-aware anchor may move more than 30 minutes but preserves interval", () => {
  const proposal = proposeExactSleepAwareAnchor({
    anchorLocalTime: "00:30",
    intervalHours: 8,
    sleep: { startLocalTime: "23:00", endLocalTime: "07:00" },
    horizonDoseCount: 9,
  });
  assertEquals(proposal.enteredIntervalMinutes, 480);
  assert(proposal.shiftMinutes >= 0);
  assert(proposal.sleepHitsAfter <= proposal.sleepHitsBefore);
});

Deno.test("exact mode keeps 6h 8h 12h 24h 48h canonical intervals", () => {
  for (finalHours in [6, 8, 12, 24, 48]) {
    const proposal = proposeExactSleepAwareAnchor({
      anchorLocalTime: "23:30",
      intervalHours: finalHours,
      sleep: { startLocalTime: "23:00", endLocalTime: "07:00" },
      horizonDoseCount: 8,
    });
    assertEquals(proposal.enteredIntervalMinutes, finalHours * 60);
  }
});

Deno.test("flexible sequence keeps every gap inside explicit user bound", () => {
  const proposal = proposeFlexibleSleepAwareSequence({
    anchorLocalTime: "22:30",
    intervalHours: 8,
    maxVariationMinutes: 30,
    doseCount: 8,
    sleep: { startLocalTime: "23:00", endLocalTime: "07:00" },
  });
  assertEquals(proposal.feasible, true);
  for (const occurrence of proposal.occurrences.slice(1)) {
    assert(occurrence.proposedGapMinutes != null);
    assert(
      occurrence.proposedGapMinutes! >= 450 &&
        occurrence.proposedGapMinutes! <= 510,
    );
    assert(Math.abs(occurrence.variationMinutes) <= 30);
  }
});

Deno.test("flexible sequence is bounded and does not mutate canonical interval", () => {
  const proposal = proposeFlexibleSleepAwareSequence({
    anchorLocalTime: "08:00",
    intervalHours: 48,
    maxVariationMinutes: 30,
    doseCount: 5,
    sleep: { startLocalTime: "23:00", endLocalTime: "07:00" },
  });
  assertEquals(proposal.enteredIntervalMinutes, 2880);
  assertEquals(proposal.occurrences.length, 5);
  assertEquals(proposal.maxVariationMinutes, 30);
});
