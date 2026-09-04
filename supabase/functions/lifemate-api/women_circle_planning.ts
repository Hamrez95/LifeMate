import type { WomenCalendarEstimate } from "./women_calendar_legacy.ts";

export type CircleSharingMode = "none" | "planning_only" | "limited_context";
export type CirclePlanningState =
  | "suitable"
  | "possibly_unsuitable"
  | "insufficient_data";

export type CircleSharingPolicy = {
  mode: CircleSharingMode;
  includePeriodWindow: boolean;
  includePhaseContext: boolean;
  includeWellbeingContext: boolean;
  revoked: boolean;
};

export type CirclePlanningContribution = {
  planningState: CirclePlanningState;
  phaseContext: "period" | "pms" | "other" | null;
  periodContext: "likely_near" | "not_near" | null;
  wellbeingContext: "shared" | null;
  evidenceLevel: "none" | "limited" | "sufficient";
};

export function normalizeCircleSharingPolicy(
  value: Record<string, unknown>,
): CircleSharingPolicy {
  const modeText = String(value.mode ?? "none").trim().toLowerCase();
  if (
    modeText !== "none" && modeText !== "planning_only" &&
    modeText !== "limited_context"
  ) {
    return disabledPolicy();
  }
  const mode = modeText as CircleSharingMode;
  if (mode === "none") return disabledPolicy();
  return {
    mode,
    includePeriodWindow: value.includePeriodWindow === true,
    includePhaseContext: value.includePhaseContext === true,
    includeWellbeingContext: value.includeWellbeingContext === true,
    revoked: value.revoked === true,
  };
}

export function deriveCirclePlanningContribution(
  policy: CircleSharingPolicy,
  estimate: WomenCalendarEstimate | null,
  hasSharedWellbeingContext: boolean,
): CirclePlanningContribution | null {
  if (policy.revoked || policy.mode === "none") return null;
  if (!estimate || estimate.confidence === "low") {
    return {
      planningState: "insufficient_data",
      phaseContext: null,
      periodContext: null,
      wellbeingContext: null,
      evidenceLevel: "none",
    };
  }

  const likelyPeriodImpact = estimate.estimatedBleeding ||
    estimate.daysUntilNextPeriod <= 2;
  const planningState: CirclePlanningState = likelyPeriodImpact
    ? "possibly_unsuitable"
    : "suitable";

  if (policy.mode === "planning_only") {
    return {
      planningState,
      phaseContext: null,
      periodContext: null,
      wellbeingContext: null,
      evidenceLevel: estimate.confidence === "high" ? "sufficient" : "limited",
    };
  }

  const detailed = String(estimate.detailedPhase ?? "");
  const phaseContext = policy.includePhaseContext
    ? detailed === "period" ? "period" : detailed === "pms" ? "pms" : "other"
    : null;
  const periodContext = policy.includePeriodWindow
    ? likelyPeriodImpact ? "likely_near" : "not_near"
    : null;

  return {
    planningState,
    phaseContext,
    periodContext,
    wellbeingContext:
      policy.includeWellbeingContext && hasSharedWellbeingContext
        ? "shared"
        : null,
    evidenceLevel: estimate.confidence === "high" ? "sufficient" : "limited",
  };
}

export function aggregateCirclePlanningWindow(
  contributions: Array<CirclePlanningContribution | null>,
): {
  summary: CirclePlanningState;
  contributingMembers: number;
  unavailableMembers: number;
} {
  const active = contributions.filter(
    (value): value is CirclePlanningContribution => value != null,
  );
  if (active.length === 0) {
    return {
      summary: "insufficient_data",
      contributingMembers: 0,
      unavailableMembers: contributions.length,
    };
  }
  const informative = active.filter((value) =>
    value.planningState !== "insufficient_data"
  );
  if (informative.length === 0) {
    return {
      summary: "insufficient_data",
      contributingMembers: active.length,
      unavailableMembers: contributions.length - active.length,
    };
  }
  const unsuitable = informative.filter(
    (value) => value.planningState === "possibly_unsuitable",
  ).length;
  return {
    summary: unsuitable > 0 ? "possibly_unsuitable" : "suitable",
    contributingMembers: active.length,
    unavailableMembers: contributions.length - active.length,
  };
}

function disabledPolicy(): CircleSharingPolicy {
  return {
    mode: "none",
    includePeriodWindow: false,
    includePhaseContext: false,
    includeWellbeingContext: false,
    revoked: false,
  };
}
