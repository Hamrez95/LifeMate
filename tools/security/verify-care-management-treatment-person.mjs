import { readFileSync } from "node:fs";

const index = readFileSync(
  "supabase/functions/lifemate-care-management/index.ts",
  "utf8",
);
const store = readFileSync(
  "supabase/functions/lifemate-care-management/person_treatment_management.ts",
  "utf8",
);

function requireMarker(source, marker, context) {
  if (!source.includes(marker)) {
    throw new Error(`${context} missing: ${marker}`);
  }
}

function requirePattern(source, pattern, context) {
  if (!pattern.test(source)) {
    throw new Error(`${context} missing semantic pattern: ${pattern}`);
  }
}

for (const marker of [
  'import { createPersonTreatmentManagementStore } from "./person_treatment_management.ts";',
  "const personTreatmentManagement = createPersonTreatmentManagementStore",
]) {
  requireMarker(index, marker, "Care Management Person treatment wiring");
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
  requireMarker(treatmentRoutes, marker, "Active Treatment route contract");
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
  "insert into lifemate.audit_logs",
  "actor_user_id",
  "resource_type",
  "resource_id",
  "metadata_json",
]) {
  requireMarker(store, marker, "Person Treatment store contract");
}
requirePattern(
  store,
  /patient_person_id\s*=\s*\$\{patientPersonId\}::uuid/,
  "Person Treatment plan ownership",
);
requirePattern(
  store,
  /owner_person_id\s*=\s*\$\{patientPersonId\}::uuid/,
  "Person Medication ownership",
);
requirePattern(
  store,
  /'treatment_plan'\s*,\s*\$\{planId\}::uuid\s*,\s*null\s*,\s*now\(\)/,
  "Treatment audit resource semantics",
);

console.log("Care Management Treatment Person boundary verified.");
