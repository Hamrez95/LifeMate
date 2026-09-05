import { ApiError } from "./validation.ts";

export type WomenHealthLifecycleState =
  | "active"
  | "paused_for_pregnancy"
  | "postpartum_recovery"
  | "resumable";

export type PregnancyTransitionEligibility = {
  womenHealthEligible: boolean;
  periodOwnedOrActive: boolean;
  cocoonEntitled: boolean;
  transitionFeatureEnabled: boolean;
};

export function evaluatePregnancyTransitionEligibility(
  value: PregnancyTransitionEligibility,
): { allowed: true } | { allowed: false; reason: string } {
  if (!value.transitionFeatureEnabled) {
    return { allowed: false, reason: "pregnancy_transition_unavailable" };
  }
  if (!value.womenHealthEligible) {
    return { allowed: false, reason: "women_health_not_eligible" };
  }
  if (!value.periodOwnedOrActive) {
    return { allowed: false, reason: "period_entitlement_required" };
  }
  if (!value.cocoonEntitled) {
    return { allowed: false, reason: "cocoon_entitlement_required" };
  }
  return { allowed: true };
}

export function nextWomenHealthLifecycleState(
  current: WomenHealthLifecycleState,
  action:
    | "activate_pregnancy"
    | "mark_postpartum"
    | "mark_resumable"
    | "resume",
): WomenHealthLifecycleState {
  if (action === "activate_pregnancy") {
    if (current === "paused_for_pregnancy") return current;
    if (current !== "active") throw invalidTransition(current, action);
    return "paused_for_pregnancy";
  }
  if (action === "mark_postpartum") {
    if (current === "postpartum_recovery") return current;
    if (current !== "paused_for_pregnancy") {
      throw invalidTransition(current, action);
    }
    return "postpartum_recovery";
  }
  if (action === "mark_resumable") {
    if (current === "resumable") return current;
    if (current !== "postpartum_recovery") {
      throw invalidTransition(current, action);
    }
    return "resumable";
  }
  if (current !== "resumable") throw invalidTransition(current, action);
  return "active";
}

export function womenHealthRuntimePolicy(state: WomenHealthLifecycleState) {
  const periodRuntimeActive = state === "active";
  return {
    preserveHistoricalCycles: true,
    allowPeriodPrediction: periodRuntimeActive,
    allowPeriodReminders: periodRuntimeActive,
    allowCycleInsights: periodRuntimeActive,
    allowNewPeriodTracking: periodRuntimeActive,
    revealPregnancyToCircle: false,
    mutateRelationshipPermissions: false,
    mutateConsentScopes: false,
    grantCocoonEntitlement: false,
  } as const;
}

function invalidTransition(
  current: WomenHealthLifecycleState,
  action: string,
): ApiError {
  return new ApiError(
    409,
    "invalid_women_health_lifecycle_transition",
    `Cannot ${action} while Women Health lifecycle is ${current}.`,
  );
}
