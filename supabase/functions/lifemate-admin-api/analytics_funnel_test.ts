import {
  ACTIVATION_FUNNEL_PRIVACY_THRESHOLD,
  KPI_DEFINITIONS,
} from "./analytics_catalog.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("activation funnel stages are ordered and privacy-bounded", () => {
  const stages = KPI_DEFINITIONS.filter((definition) =>
    definition.funnel?.id === "activation"
  );

  assert(
    stages.length === 2,
    "activation funnel must expose exactly two truthful stages",
  );
  assert(
    stages[0]?.name === "activation_enrolled_accounts",
    "stage 1 must be enrollment cohort",
  );
  assert(stages[0]?.funnel?.stageOrder === 1, "stage 1 order must be stable");
  assert(
    stages[0]?.funnel?.previousStage === null,
    "stage 1 has no previous stage",
  );
  assert(
    stages[1]?.name === "activation_observed_accounts",
    "stage 2 must be observed activation",
  );
  assert(stages[1]?.funnel?.stageOrder === 2, "stage 2 order must be stable");
  assert(
    stages[1]?.funnel?.previousStage === "activation_enrolled_accounts",
    "stage 2 must reference the canonical preceding stage",
  );
  assert(
    stages.every(
      (stage) =>
        stage.funnel?.privacyThreshold === ACTIVATION_FUNNEL_PRIVACY_THRESHOLD,
    ),
    "all stages must share the aggregate privacy threshold",
  );
});

Deno.test("activation rate is computed by Core from the same funnel cohort", () => {
  const rate = KPI_DEFINITIONS.find((definition) =>
    definition.name === "activation_observed_rate"
  );

  assert(rate?.unit === "rate", "activation rate must be typed as a rate");
  assert(
    rate?.numerator === "activation_observed_accounts",
    "activation rate numerator must be the second funnel stage",
  );
  assert(
    rate?.denominator === "activation_enrolled_accounts",
    "activation rate denominator must be the first funnel stage",
  );
  assert(
    rate?.eventSources.includes("app_activation_observed"),
    "activation rate must document its canonical snapshot source",
  );
});
