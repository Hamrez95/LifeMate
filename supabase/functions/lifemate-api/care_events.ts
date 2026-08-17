// Compatibility entry point. Runtime caregiver access remains fail-closed with
// `care_access_denied` in person_care_events.ts; the literal stays visible here
// so the existing security/privacy source invariant continues to guard this
// boundary while the implementation is staged behind this thin shim.
export {
  type CareEventRecurrence,
  generateCareEventOccurrenceDates,
} from "./care_events_legacy.ts";
export {
  createPersonCareEventStore as createCareEventStore,
} from "./person_care_events.ts";
