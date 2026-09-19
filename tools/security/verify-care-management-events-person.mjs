import { readFileSync } from "node:fs";

const index = readFileSync(
  "supabase/functions/lifemate-care-management/index.ts",
  "utf8",
);
const store = readFileSync(
  "supabase/functions/lifemate-care-management/person_care_event_management.ts",
  "utf8",
);

for (const marker of [
  'import { createPersonCareEventManagementStore } from "./person_care_event_management.ts";',
  "const personCareEventManagement = createPersonCareEventManagementStore",
]) {
  if (!index.includes(marker)) {
    throw new Error(`Care Management Person Care Event wiring missing: ${marker}`);
  }
}

const routeStart = index.indexOf("const eventsMatch = path.match(");
const routeEnd = index.indexOf('throw new ApiError(404, "route_not_found"');
if (routeStart < 0 || routeEnd <= routeStart) {
  throw new Error("Care Management Care Event route block could not be isolated.");
}
const eventRoutes = index.slice(routeStart, routeEnd);
for (const marker of [
  "await requireManagementAccess(appUserId, eventsMatch[1])",
  "await requireManagementAccess(appUserId, eventMatch[1])",
  "personCareEventManagement.listCareEvents",
  "personCareEventManagement.createCareEvent",
  "personCareEventManagement.updateCareEvent",
  "personCareEventManagement.cancelCareEvent",
]) {
  if (!eventRoutes.includes(marker)) {
    throw new Error(`Active Care Event route contract missing: ${marker}`);
  }
}
for (const forbidden of [
  "return json(await listCareEvents(",
  "await createCareEvent(",
  "await updateCareEvent(",
  "await cancelCareEvent(",
]) {
  if (eventRoutes.includes(forbidden)) {
    throw new Error(`Active route regressed to legacy Care Event helper: ${forbidden}`);
  }
}

for (const forbidden of ["patient_user_id", "{ patientUserId }"]) {
  if (store.includes(forbidden)) {
    throw new Error(
      `Person Care Event store must not depend on legacy patient ownership: ${forbidden}`,
    );
  }
}

const personStoreContracts = [
  [
    /self_person_id_for_legacy_app_user/,
    "Care Event ownership must resolve through the canonical self Person mapping",
  ],
  [
    /patient_person_id\s*=\s*\$\{personId\}::uuid/,
    "Care Event reads and mutations must remain scoped by patient_person_id",
  ],
  [
    /\(id,\s*patient_person_id,\s*created_by_user_id,\s*client_request_id/,
    "Care Event inserts must persist Person ownership and creator identity",
  ],
  [
    /\$\{caregiverAppUserId\}::uuid/,
    "Care Event writes must preserve the acting caregiver identity",
  ],
  [
    /client_request_id\s*=\s*\$\{input\.clientRequestId\}::uuid/,
    "Care Event idempotency lookup must remain Person-scoped",
  ],
  [
    /['"]care_event['"]\s*,\s*\$\{eventId\}::uuid/,
    "Care Event audit records must identify the Care Event without patient AppUser ownership",
  ],
];
for (const [pattern, message] of personStoreContracts) {
  if (!pattern.test(store)) {
    throw new Error(`Person Care Event store contract missing: ${message}`);
  }
}
if (
  !/const metadata\s*=\s*eventType\s*==\s*null\s*\?\s*null\s*:\s*JSON\.stringify\(\{\s*eventType\s*\}\)/.test(
    store,
  )
) {
  throw new Error(
    "Care Event audit metadata must serialize event semantics without patient AppUser identity.",
  );
}

// The staged relationship permission/consent boundary intentionally remains
// unchanged in this slice; removing it would broaden access.
for (const marker of [
  "async function requireManagementAccess",
  "patient_user_id = ${patientUserId}::uuid",
  "caregiver_user_id = ${caregiverUserId}::uuid",
  "can_manage_health_record = true",
]) {
  if (!index.includes(marker)) {
    throw new Error(`Care relationship permission gate changed unexpectedly: ${marker}`);
  }
}

console.log("Care Management Care Event Person boundary verified.");
