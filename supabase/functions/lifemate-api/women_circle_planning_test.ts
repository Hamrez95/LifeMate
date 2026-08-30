import { assertEquals } from "jsr:@std/assert@1";
import {
  aggregateCirclePlanningWindow,
  deriveCirclePlanningContribution,
  normalizeCircleSharingPolicy,
} from "./women_circle_planning.ts";

const estimate = {
  cycleStart: "2026-08-05",
  cycleDay: 27,
  cycleLength: 28,
  periodLength: 5,
  estimatedBleeding: false,
  phase: "pre_period" as const,
  detailedPhase: "pms" as const,
  ovulationDay: 14,
  fertileWindowStartDay: 9,
  fertileWindowEndDay: 15,
  pmsStartDay: 24,
  nextPeriodStart: "2026-09-02",
  daysUntilNextPeriod: 1,
  algorithmVersion: "calendar-estimate-v1" as const,
  confidence: "high" as const,
  cyclePattern: "regular" as const,
  fertilityEstimateReliable: true,
};

Deno.test("no-sharing member contributes nothing", () => {
  const policy = normalizeCircleSharingPolicy({ mode: "none" });
  assertEquals(deriveCirclePlanningContribution(policy, estimate, true), null);
});

Deno.test("planning-only reveals no exact cycle or phase context", () => {
  const policy = normalizeCircleSharingPolicy({
    mode: "planning_only",
    includePeriodWindow: true,
    includePhaseContext: true,
    includeWellbeingContext: true,
  });
  assertEquals(deriveCirclePlanningContribution(policy, estimate, true), {
    planningState: "possibly_unsuitable",
    phaseContext: null,
    periodContext: null,
    wellbeingContext: null,
    evidenceLevel: "sufficient",
  });
});

Deno.test("limited context exposes only fields explicitly selected", () => {
  const policy = normalizeCircleSharingPolicy({
    mode: "limited_context",
    includePeriodWindow: false,
    includePhaseContext: true,
    includeWellbeingContext: false,
  });
  assertEquals(deriveCirclePlanningContribution(policy, estimate, true), {
    planningState: "possibly_unsuitable",
    phaseContext: "pms",
    periodContext: null,
    wellbeingContext: null,
    evidenceLevel: "sufficient",
  });
});

Deno.test("revocation immediately removes future contribution", () => {
  const policy = normalizeCircleSharingPolicy({
    mode: "limited_context",
    includePeriodWindow: true,
    revoked: true,
  });
  assertEquals(deriveCirclePlanningContribution(policy, estimate, false), null);
});

Deno.test("insufficient evidence reveals only insufficient-data state", () => {
  const policy = normalizeCircleSharingPolicy({ mode: "planning_only" });
  assertEquals(
    deriveCirclePlanningContribution(
      policy,
      { ...estimate, confidence: "low" as const },
      false,
    ),
    {
      planningState: "insufficient_data",
      phaseContext: null,
      periodContext: null,
      wellbeingContext: null,
      evidenceLevel: "none",
    },
  );
});

Deno.test("group aggregate never includes member raw health fields", () => {
  const summary = aggregateCirclePlanningWindow([
    {
      planningState: "suitable",
      phaseContext: null,
      periodContext: null,
      wellbeingContext: null,
      evidenceLevel: "sufficient",
    },
    null,
    {
      planningState: "possibly_unsuitable",
      phaseContext: null,
      periodContext: null,
      wellbeingContext: null,
      evidenceLevel: "limited",
    },
  ]);
  assertEquals(summary, {
    summary: "possibly_unsuitable",
    contributingMembers: 2,
    unavailableMembers: 1,
  });
});
