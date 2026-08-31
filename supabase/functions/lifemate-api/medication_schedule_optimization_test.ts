import { assertEquals } from "jsr:@std/assert@1";
import {
  buildNearbyDoseProposal,
  type NearbyDosePlanCandidate,
} from "./medication_schedule_optimization.ts";

function plan(
  id: string,
  time: string,
  overrides: Partial<NearbyDosePlanCandidate> = {},
): NearbyDosePlanCandidate {
  return {
    treatmentPlanId: id,
    medicationName: `Medication ${id}`,
    anchorLocalTime: time,
    intervalHours: 8,
    treatmentPlanVersion: 1,
    timingVersion: 1,
    nearbyGroupingEnabled: true,
    timingLocked: false,
    manualSpacingBeforeMinutes: 0,
    manualSpacingAfterMinutes: 0,
    ...overrides,
  };
}

Deno.test("nearby proposal groups strictly-under-30-minute anchors and preserves exact intervals", () => {
  const proposal = buildNearbyDoseProposal([
    plan("a", "08:00", { intervalHours: 8 }),
    plan("b", "08:20", { intervalHours: 12 }),
  ]);
  assertEquals(proposal.groups.length, 1);
  assertEquals(proposal.groups[0].sharedLocalTime, "08:10");
  assertEquals(
    proposal.groups[0].changes.map((change) => [
      change.intervalHoursBefore,
      change.intervalHoursAfter,
    ]),
    [[8, 8], [12, 12]],
  );
  assertEquals(proposal.expectedNotificationReduction, 1);
});

Deno.test("29 minutes remains eligible", () => {
  const proposal = buildNearbyDoseProposal([
    plan("a", "08:00"),
    plan("b", "08:29"),
  ]);
  assertEquals(proposal.groups.length, 1);
  assertEquals(proposal.groups[0].sharedLocalTime, "08:15");
});

Deno.test("exactly 30 minutes is excluded", () => {
  const proposal = buildNearbyDoseProposal([
    plan("a", "08:00"),
    plan("b", "08:30"),
  ]);
  assertEquals(proposal.groups.length, 0);
  assertEquals(
    proposal.exclusions.map((value) => value.reason),
    ["no_nearby_candidate", "no_nearby_candidate"],
  );
});

Deno.test("31 minutes is excluded", () => {
  const proposal = buildNearbyDoseProposal([
    plan("a", "08:00"),
    plan("b", "08:31"),
  ]);
  assertEquals(proposal.groups.length, 0);
  assertEquals(
    proposal.exclusions.map((value) => value.reason),
    ["no_nearby_candidate", "no_nearby_candidate"],
  );
});

Deno.test("midnight crossing uses circular distance", () => {
  const proposal = buildNearbyDoseProposal([
    plan("a", "23:55"),
    plan("b", "00:10"),
  ]);
  assertEquals(proposal.groups.length, 1);
  assertEquals(proposal.groups[0].sharedLocalTime, "00:05");
});

Deno.test("locked, not-opted-in and manual-spacing plans fail closed", () => {
  const proposal = buildNearbyDoseProposal([
    plan("a", "08:00", { timingLocked: true }),
    plan("b", "08:05", { nearbyGroupingEnabled: false }),
    plan("c", "08:10", { manualSpacingBeforeMinutes: 15 }),
  ]);
  assertEquals(proposal.groups.length, 0);
  assertEquals(
    proposal.exclusions.map((value) => value.reason),
    ["timing_locked", "not_opted_in", "manual_spacing"],
  );
});

Deno.test("ambiguous transitive chain is omitted instead of shifting contradictory plans", () => {
  const proposal = buildNearbyDoseProposal([
    plan("a", "08:00"),
    plan("b", "08:25"),
    plan("c", "08:50"),
  ]);
  assertEquals(proposal.groups.length, 0);
  assertEquals(
    proposal.exclusions.map((value) => value.reason),
    ["ambiguous_cluster", "ambiguous_cluster", "ambiguous_cluster"],
  );
});

Deno.test("6h 8h 12h 24h and 48h recurrence remain exact after proposal", () => {
  const intervals = [6, 8, 12, 24, 48];
  for (const intervalHours of intervals) {
    const proposal = buildNearbyDoseProposal([
      plan(`a-${intervalHours}`, "06:00", { intervalHours }),
      plan(`b-${intervalHours}`, "06:10", { intervalHours }),
    ]);
    assertEquals(proposal.groups.length, 1);
    assertEquals(
      proposal.groups[0].changes.every(
        (value) =>
          value.intervalHoursBefore === intervalHours &&
          value.intervalHoursAfter === intervalHours,
      ),
      true,
    );
  }
});
