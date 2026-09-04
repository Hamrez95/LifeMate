import { readFileSync } from "node:fs";

const index = readFileSync(
  "supabase/functions/lifemate-care-management/index.ts",
  "utf8",
);
const store = readFileSync(
  "supabase/functions/lifemate-care-management/person_treatment_management.ts",
  "utf8",
);

for (const marker of [
  'import { createPersonTreatmentManagementStore } from "./person_treatment_management.ts";',
  "const personTreatmentManagement = createPersonTreatmentManagementStore",
]) {
  if (!index.includes(marker)) {
    throw new Error(`Care Management Person treatment wiring missing: ${marker}`);
  }
}

const routeStart = index.indexOf("const plansMatch = path.match(");
const routeEnd = index.indexOf("const eventsMatch = path.match(");
if (routeStart < 0 || routeEnd <= routeStart) {
  throw new Error("Care Management Treatment route block could not be isolated.");
}
const treatmentRoutes = index.slice(routeStart, routeEnd);
for (const marker of [
  "await requireManagementAccess(appUserId, plansMatch[1])",
  "await requireManagementAccess(appUserId, planMatch[1])",
  "personTreatmentManagement.listTreatmentPlans",
  "personTreatmentManagement.createTreatmentPlan",
  "personTreatmentManagement.updateTreatmentPlan",
  "personTreatmentManagement.archiveTreatmentPlan",
]) {
  if (!treatmentRoutes.includes(marker)) {
    throw new Error(`Active Treatment route contract missing: ${marker}`);
  }
}
for (const forbidden of [
  "return json(await listTreatmentPlans(",
  "await createTreatmentPlan(",
  "await updateTreatmentPlan(",
  "await archiveTreatmentPlan(",
]) {
  if (treatmentRoutes.includes(forbidden)) {
    throw new Error(`Active route regressed to legacy Treatment helper: ${forbidden}`);
  }
}

for (const forbidden of [
  "patient_user_id",
  "owner_user_id",
  "{ patientUserId }",
]) {
  if (store.includes(forbidden)) {
    throw new Error(
      `Person Treatment store must not depend on legacy patient ownership: ${forbidden}`,
    );
  }
}
for (const marker of [
  "self_person_id_for_legacy_app_user",
  "p.patient_person_id",
  "m.owner_person_id",
  "insert into lifemate.medications",
  "(id, owner_person_id, name",
  "insert into lifemate.treatment_plans",
  "(id, patient_person_id, medication_id",
]) {
  if (!store.includes(marker)) {
    throw new Error(`Person Treatment store contract missing: ${marker}`);
  }
}

for (const [name, pattern] of [
  [
    "patient Person ownership predicate",
    /patient_person_id\s*=\s*\$\{patientPersonId\}::uuid/,
  ],
  [
    "medication Person ownership predicate",
    /owner_person_id\s*=\s*\$\{patientPersonId\}::uuid/,
  ],
  [
    "treatment audit column contract",
    /insert\s+into\s+lifemate\.audit_logs\s*\(\s*id\s*,\s*actor_user_id\s*,\s*action\s*,\s*resource_type\s*,\s*resource_id\s*,\s*metadata_json\s*,\s*created_at_utc\s*\)/i,
  ],
  [
    "treatment audit resource contract",
    /\$\{action\}\s*,\s*['"]treatment_plan['"]\s*,\s*\$\{planId\}::uuid\s*,\s*null\s*,\s*now\(\)\s*\)/i,
  ],
]) {
  if (!pattern.test(store)) {
    throw new Error(`Person Treatment store contract missing: ${name}`);
  }
}

console.log("Care Management Treatment Person boundary verified.");
