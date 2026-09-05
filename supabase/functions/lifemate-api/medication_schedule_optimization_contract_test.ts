import { assert, assertEquals } from "jsr:@std/assert@1";
import { buildNearbyDoseProposal } from "./medication_schedule_optimization.ts";

Deno.test("regression: 29m groups while 30m and 31m do not", () => {
  const base = (id: string, anchorLocalTime: string) => ({
    treatmentPlanId: id,
    medicationName: id,
    anchorLocalTime,
    intervalHours: 8,
    treatmentPlanVersion: 4,
    timingVersion: 2,
    nearbyGroupingEnabled: true,
    timingLocked: false,
    manualSpacingBeforeMinutes: 0,
    manualSpacingAfterMinutes: 0,
  });
  assertEquals(
    buildNearbyDoseProposal([base("a", "08:00"), base("b", "08:29")]).groups
      .length,
    1,
  );
  assertEquals(
    buildNearbyDoseProposal([base("a", "08:00"), base("b", "08:30")]).groups
      .length,
    0,
  );
  assertEquals(
    buildNearbyDoseProposal([base("a", "08:00"), base("b", "08:31")]).groups
      .length,
    0,
  );
});

Deno.test("regression: strict nearby proposal preserves every canonical hourly interval", () => {
  for (const intervalHours of [6, 8, 12, 24, 48]) {
    const proposal = buildNearbyDoseProposal([
      {
        treatmentPlanId: `a-${intervalHours}`,
        medicationName: "a",
        anchorLocalTime: "08:00",
        intervalHours,
        treatmentPlanVersion: 4,
        timingVersion: 2,
        nearbyGroupingEnabled: true,
        timingLocked: false,
        manualSpacingBeforeMinutes: 0,
        manualSpacingAfterMinutes: 0,
      },
      {
        treatmentPlanId: `b-${intervalHours}`,
        medicationName: "b",
        anchorLocalTime: "08:20",
        intervalHours,
        treatmentPlanVersion: 7,
        timingVersion: 3,
        nearbyGroupingEnabled: true,
        timingLocked: false,
        manualSpacingBeforeMinutes: 0,
        manualSpacingAfterMinutes: 0,
      },
    ]);
    assert(proposal.groups.length === 1);
    assert(
      proposal.groups[0].changes.every(
        (change) =>
          change.intervalHoursBefore === intervalHours &&
          change.intervalHoursAfter === intervalHours,
      ),
    );
  }
});

Deno.test("regression: server apply sources pin treatment timing and preference versions", async () => {
  const nearbyStore = await Deno.readTextFile(
    new URL("./medication_schedule_optimization_store.ts", import.meta.url),
  );
  assert(nearbyStore.includes("expected_treatment_plan_version"));
  assert(nearbyStore.includes("expected_timing_version"));
  assert(nearbyStore.includes("stale_schedule_proposal"));
  assert(
    nearbyStore.includes("intervalHours !== Number(change.interval_hours)"),
  );

  const sleepStore = await Deno.readTextFile(
    new URL("./medication_schedule_sleep_store.ts", import.meta.url),
  );
  assert(sleepStore.includes("schedule_preferences_version"));
  assert(sleepStore.includes("stale_sleep_preferences"));
  assert(sleepStore.includes("acknowledgedTimingChanges !== true"));
  assert(sleepStore.includes("timing_acknowledgement_required"));
});
