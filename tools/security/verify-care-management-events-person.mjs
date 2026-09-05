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
for (const marker of [
  "self_person_id_for_legacy_app_user",
  "${caregiverAppUserId}::uuid",
]) {
  if (!store.includes(marker)) {
    throw new Error(`Person Care Event store contract missing: ${marker}`);
  }
}
for (const [name, pattern] of [
  [
    "patient Person ownership predicate",
    /patient_person_id\s*=\s*\$\{personId\}::uuid/,
  ],
  [
    "Person-authoritative care event insert",
    /insert\s+into\s+lifemate\.care_events\s*\(\s*id\s*,\s*patient_person_id\s*,\s*created_by_user_id\s*,\s*client_request_id\b/i,
  ],
  [
    "care event idempotency predicate",
    /client_request_id\s*=\s*\$\{input\.clientRequestId\}::uuid/,
  ],
  [
    "care event audit resource contract",
    /values\s*\([\s\S]*?\$\{action\}\s*,\s*['"]care_event['"]\s*,\s*\$\{eventId\}::uuid\s*,\s*\$\{metadata\}::jsonb\s*,\s*now\(\)\s*\)/i,
  ],
]) {
  if (!pattern.test(store)) {
    throw new Error(`Person Care Event store contract missing: ${name}`);
  }
}
if (!store.includes("const metadata = eventType == null ? null : JSON.stringify({ eventType })")) {
  throw new Error(
    "Care Event audit metadata must keep event semantics without patient AppUser identity.",
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
