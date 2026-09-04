import {
  selectWeightedExperimentVariant,
  stableExperimentBucket,
} from "../_shared/experiment_assignment.ts";
import {
  createExperimentAssignmentStore,
  parseExperimentAssignmentProduct,
} from "./experiment_assignments.ts";
import { ApiError } from "./validation.ts";

Deno.test("experiment product parsing is canonical and bounded", () => {
  if (parseExperimentAssignmentProduct(" WellMate ") !== "wellmate") {
    throw new Error("Product normalization failed.");
  }
  let rejected = false;
  try {
    parseExperimentAssignmentProduct("wellmate<script>");
  } catch (error) {
    rejected = error instanceof ApiError &&
      error.code === "experiment_product_invalid";
  }
  if (!rejected) throw new Error("Invalid experiment product was accepted.");
});

Deno.test("consumer and admin assignment primitive is deterministic", async () => {
  const first = await stableExperimentBucket(
    "pricing.paywall.v1",
    "account:550e8400-e29b-41d4-a716-446655440000",
  );
  const second = await stableExperimentBucket(
    "pricing.paywall.v1",
    "account:550e8400-e29b-41d4-a716-446655440000",
  );
  if (first !== second || first < 0 || first >= 10_000) {
    throw new Error("Stable experiment bucket is not deterministic.");
  }
  const variants = [
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
      version: 1,
    },
  ];
  const selected = selectWeightedExperimentVariant(variants, first);
  if (!selected || !["control", "candidate"].includes(selected.key)) {
    throw new Error("Weighted variant selection failed.");
  }
});

Deno.test("experiment assignment store refuses weak pseudonymization secret", () => {
  let rejected = false;
  try {
    createExperimentAssignmentStore(
      "postgres://lifemate_edge_runtime:password@localhost:5432/lifemate",
      "too-short",
    );
  } catch (error) {
    rejected = error instanceof Error &&
      error.message.includes("hashing secret is not configured safely");
  }
  if (!rejected) {
    throw new Error("Weak experiment pseudonymization secret was accepted.");
  }
});
