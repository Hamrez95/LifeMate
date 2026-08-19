import { readFileSync } from "node:fs";

const tool = readFileSync(
  "tools/security/treatment-dose-owner-retirement.ts",
  "utf8",
);
const treatments = readFileSync(
  "supabase/functions/lifemate-api/person_treatment_plans.ts",
  "utf8",
);
const doses = readFileSync(
  "supabase/functions/lifemate-api/person_dose_occurrences.ts",
  "utf8",
);

for (const marker of [
  "treatment_dose_owner_retirement_readiness_vacuous",
  "treatment_dose_owner_retirement_mapping_missing",
  "treatment_dose_owner_retirement_mapping_ambiguous",
  "treatment_dose_owner_retirement_mapping_mismatch",
  "treatment_dose_owner_retirement_dose_plan_mismatch",
  "SCRUB-TREATMENT-DOSE-OWNERS",
  "REHYDRATE-TREATMENT-DOSE-OWNERS",
  "dose_plan_person_mismatches",
  "set patient_user_id=null",
  "set patient_user_id=${mapping.legacy_app_user_id}::uuid",
]) {
  if (!tool.includes(marker)) {
    throw new Error(`Treatment/Dose owner retirement contract is missing: ${marker}`);
  }
}

if (/\b(delete\s+from|truncate)\s+lifemate\.(treatment_plans|dose_occurrences)/i.test(tool)) {
  throw new Error(
    "Treatment/Dose owner retirement tooling must not delete healthcare rows.",
  );
}

for (const [name, source, table] of [
  ["Treatment Plan", treatments, "treatment_plans"],
  ["Dose occurrence", doses, "dose_occurrences"],
]) {
  const insertPattern = new RegExp(
    `insert\\s+into\\s+lifemate\\.${table}\\s*\\([^)]*patient_user_id`,
    "is",
  );
  if (insertPattern.test(source)) {
    throw new Error(`${name} runtime must not write legacy patient_user_id ownership.`);
  }
}

for (const marker of [
  "patient_person_id",
  "createPersonTreatmentPlanStore",
]) {
  if (!treatments.includes(marker)) {
    throw new Error(`Person-authoritative Treatment Plan boundary is missing: ${marker}`);
  }
}
for (const marker of [
  "patient_person_id",
  "createPersonDoseOccurrenceStore",
  "actor_user_id",
  "client_request_id",
]) {
  if (!doses.includes(marker)) {
    throw new Error(`Dose Person/provenance boundary is missing: ${marker}`);
  }
}

console.log("Treatment/Dose owner retirement boundary verified.");
