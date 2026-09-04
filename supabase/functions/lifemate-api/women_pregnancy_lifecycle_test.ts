import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  evaluatePregnancyTransitionEligibility,
  nextWomenHealthLifecycleState,
  womenHealthRuntimePolicy,
} from "./women_pregnancy_lifecycle.ts";

Deno.test("pregnancy transition requires canonical product eligibility", () => {
  assertEquals(
    evaluatePregnancyTransitionEligibility({
      womenHealthEligible: true,
      periodOwnedOrActive: true,
      cocoonEntitled: false,
      transitionFeatureEnabled: true,
    }),
    { allowed: false, reason: "cocoon_entitlement_required" },
  );
  assertEquals(
    evaluatePregnancyTransitionEligibility({
      womenHealthEligible: true,
      periodOwnedOrActive: true,
      cocoonEntitled: true,
      transitionFeatureEnabled: true,
    }),
    { allowed: true },
  );
});

Deno.test("pregnancy activation is idempotent and does not skip lifecycle states", () => {
  assertEquals(
    nextWomenHealthLifecycleState("active", "activate_pregnancy"),
    "paused_for_pregnancy",
  );
  assertEquals(
    nextWomenHealthLifecycleState("paused_for_pregnancy", "activate_pregnancy"),
    "paused_for_pregnancy",
  );
  assertThrows(() => nextWomenHealthLifecycleState("active", "resume"));
});

Deno.test("postpartum lifecycle requires explicit resumable then resume", () => {
  assertEquals(
    nextWomenHealthLifecycleState("paused_for_pregnancy", "mark_postpartum"),
    "postpartum_recovery",
  );
  assertEquals(
    nextWomenHealthLifecycleState("postpartum_recovery", "mark_resumable"),
    "resumable",
  );
  assertEquals(nextWomenHealthLifecycleState("resumable", "resume"), "active");
});

Deno.test("paused runtime preserves history while stopping incompatible period behavior", () => {
  assertEquals(womenHealthRuntimePolicy("paused_for_pregnancy"), {
    preserveHistoricalCycles: true,
    allowPeriodPrediction: false,
    allowPeriodReminders: false,
    allowCycleInsights: false,
    allowNewPeriodTracking: false,
    revealPregnancyToCircle: false,
    mutateRelationshipPermissions: false,
    mutateConsentScopes: false,
    grantCocoonEntitlement: false,
  });
});

Deno.test("active runtime never implies commerce or privacy mutation", () => {
  const policy = womenHealthRuntimePolicy("active");
  assertEquals(policy.allowPeriodPrediction, true);
  assertEquals(policy.grantCocoonEntitlement, false);
  assertEquals(policy.mutateRelationshipPermissions, false);
  assertEquals(policy.mutateConsentScopes, false);
  assertEquals(policy.revealPregnancyToCircle, false);
});
