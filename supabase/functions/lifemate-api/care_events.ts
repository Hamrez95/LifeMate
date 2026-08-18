// Compatibility entry point. Runtime caregiver access remains fail-closed with
// `care_access_denied`; the public facade authorizes the active relationship by
// canonical patient/caregiver Person IDs before selecting Person-owned events.
export {
  type CareEventRecurrence,
  generateCareEventOccurrenceDates,
} from "./care_events_legacy.ts";
export {
  createPersonAuthorizedCareEventStore as createCareEventStore,
} from "./person_care_events_facade.ts";
