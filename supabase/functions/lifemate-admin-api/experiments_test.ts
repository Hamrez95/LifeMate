import {
  assertExperimentMetrics,
  assertVariantWeights,
  assignExperimentVariant,
  type ExperimentDefinition,
  parseExperimentKey,
  parseExperimentSurface,
} from "./experiments.ts";
import { ApiError } from "./validation.ts";

function baseExperiment(): ExperimentDefinition {
  return {
    key: "pricing.paywall.v1",
    name: "Pricing paywall experiment",
    controlKey: "pricing.paywall.variant",
    surface: "paywall",
    productCode: "wellmate",
    segmentKey: null,
    primaryMetricCode: "activation_observed_rate",
    guardrailMetricCodes: ["activation_enrolled_accounts"],
    status: "Running",
    startsAtUtc: "2026-08-01T00:00:00.000Z",
    endsAtUtc: "2026-09-01T00:00:00.000Z",
    version: 3,
    variants: [
      {
        key: "control",
        weightBasisPoints: 5000,
        controlValue: false,
        version: 1,
      },
      {
        key: "candidate",
        weightBasisPoints: 5000,
        controlValue: true,
        version: 2,
      },
    ],
  };
}

Deno.test("experiment key and surface validation are bounded", () => {
  if (parseExperimentKey(" Pricing.Paywall.V1 ") !== "pricing.paywall.v1") {
    throw new Error("Experiment key normalization failed.");
  }
  if (parseExperimentSurface("paywall") !== "paywall") {
    throw new Error("Experiment surface parsing failed.");
  }
  let rejected = false;
  try {
    parseExperimentSurface("treatment_safety");
  } catch (error) {
    rejected = error instanceof ApiError &&
      error.code === "experiment_surface_invalid";
  }
  if (!rejected) {
    throw new Error("Unsafe/unsupported experiment surface was accepted.");
  }
});

Deno.test("experiment variants must total exactly 10000 basis points", () => {
  let rejected = false;
  try {
    assertVariantWeights([
      {
        key: "variant_a",
        weightBasisPoints: 5000,
        controlValue: 1,
        version: 1,
      },
      {
        key: "variant_b",
        weightBasisPoints: 4999,
        controlValue: 2,
        version: 1,
      },
    ]);
  } catch (error) {
    rejected = error instanceof ApiError &&
      error.code === "experiment_variant_weight_total_invalid";
  }
  if (!rejected) {
    throw new Error("Invalid experiment weight total was accepted.");
  }
});

Deno.test("experiment assignment is stable for the same subject and version", async () => {
  const experiment = baseExperiment();
  const context = {
    subjectKey: "account:550e8400-e29b-41d4-a716-446655440000",
    productCode: "wellmate",
    now: new Date("2026-08-20T10:00:00.000Z"),
  };
  const first = await assignExperimentVariant(experiment, context);
  const second = await assignExperimentVariant(experiment, context);
  if (!first.eligible || first.variantKey !== second.variantKey) {
    throw new Error("Stable subject assignment was not deterministic.");
  }
  if (first.bucketBasisPoints !== second.bucketBasisPoints) {
    throw new Error("Stable subject bucket changed across evaluations.");
  }
});

Deno.test("experiment assignment respects product and scheduling eligibility", async () => {
  const experiment = baseExperiment();
  const wrongProduct = await assignExperimentVariant(experiment, {
    subjectKey: "account:550e8400-e29b-41d4-a716-446655440000",
    productCode: "caremate",
    now: new Date("2026-08-20T10:00:00.000Z"),
  });
  if (wrongProduct.reason !== "product_mismatch") {
    throw new Error("Product targeting was not enforced.");
  }

  const expired = await assignExperimentVariant(experiment, {
    subjectKey: "account:550e8400-e29b-41d4-a716-446655440000",
    productCode: "wellmate",
    now: new Date("2026-09-02T00:00:00.000Z"),
  });
  if (expired.reason !== "outside_window") {
    throw new Error("Experiment end window was not enforced.");
  }
});

Deno.test("launch guard rejects canonical metrics that are not instrumented", () => {
  let rejected = false;
  try {
    assertExperimentMetrics(
      "monthly_active_accounts",
      [],
      { requireMeasurable: true },
    );
  } catch (error) {
    rejected = error instanceof ApiError &&
      error.code === "experiment_metric_unavailable";
  }
  if (!rejected) throw new Error("Unavailable metric was accepted for launch.");

  assertExperimentMetrics(
    "activation_observed_rate",
    ["activation_enrolled_accounts"],
    { requireMeasurable: true },
  );
});
