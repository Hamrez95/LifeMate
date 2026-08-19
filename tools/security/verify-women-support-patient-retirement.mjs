import { readFileSync } from "node:fs";

const runtime = readFileSync(
  "supabase/functions/lifemate-api/person_women_calendar_caregiver.ts",
  "utf8",
);
const migration = readFileSync(
  "supabase/migrations/20260819151000_retire_women_support_patient_user_write.sql",
  "utf8",
);

for (const marker of [
  "alter column patient_person_id set not null",
  "alter column patient_user_id drop not null",
  "patient_person_id is null",
]) {
  if (!migration.includes(marker)) {
    throw new Error(`Women support retirement migration is missing: ${marker}`);
  }
}

const insertMatch = runtime.match(
  /insert into lifemate\.women_calendar_support_actions\s*\(([\s\S]*?)\)\s*values/i,
);
if (!insertMatch) {
  throw new Error("Canonical Women Calendar support-action insert was not found.");
}
const insertColumns = insertMatch[1];
if (/\bpatient_user_id\b/i.test(insertColumns)) {
  throw new Error(
    "Canonical Women Calendar support writes must not persist patient_user_id.",
  );
}
for (const required of [
  "patient_person_id",
  "caregiver_user_id",
  "relationship_id",
]) {
  if (!new RegExp(`\\b${required}\\b`).test(insertColumns)) {
    throw new Error(`Canonical Women Calendar support write is missing ${required}.`);
  }
}

if (!runtime.includes("patient_person_id=${patientPersonId}::uuid")) {
  throw new Error("Women Calendar caregiver reads must remain Person-scoped.");
}
if (!runtime.includes("caregiver_person_id=${caregiverPersonId}::uuid")) {
  throw new Error("Women Calendar caregiver authorization must remain Person-scoped.");
}

console.log("Women Calendar support patient retirement boundary verified.");
