# CocoonMate UI / backend handoff v2

Status: refreshed against `origin/main` at `38d5b223` on 2026-09-12.

## Already landed

| Area | Frontend | Canonical backend / contract |
| --- | --- | --- |
| Home, Week Detail, Calendar visual language | Core visual pass and goldens landed in #1109 | Pregnancy snapshot and derived dating are host-owned |
| Calendar | Month/timeline/care-plan presentation is available | Canonical `care_events` pregnancy links landed in #1110 |
| Check-in and Symptoms | Injected catalog, state surfaces, external callbacks | Typed daily captures landed in #1122; Flutter adapter wiring remains |
| Measurements | Injected field schema and state surfaces | Canonical observations adapter landed in #1123; Flutter adapter wiring remains |
| Records | Visual record surface exists | Paginated canonical pregnancy records read model landed in #1140 |
| Medication | Care-plan item presentation exists | Treatment context landed in #1137; Flutter adapter wiring remains |

## Current visual delivery order

1. Daily tracking: Quick Add, Check-in, Symptoms, Measurements, Medication.
2. Care plan: Appointments, Reminders and Records.
3. Onboarding, Settings and scoped caregiver-sharing states.
4. Education and Safety content surfaces.
5. Final asset integration, Home/Week Detail art pass, motion and physical-device QA.

## Backend handoff rules

- Flutter must consume the reviewed API/client adapters only; it must not add a second store, scheduler, outbox, healthcare schema or clinical evaluator.
- Pregnancy week/day is derived from approved dating, never a mutable UI field.
- Clinical copy, symptom catalog and safety levels remain host-supplied and versioned.
- UI callbacks must expose `loading`, `offline cached`, `queued`, `confirmed`, `partial`, `unavailable` and `error` honestly; queued is not server confirmation.
- A frontend task can be marked complete only after RTL/LTR, large text, semantics, overflow checks and stable widget/golden coverage. A backend issue remains open until its authorized adapter, reconciliation and tests exist.

## Asset dependency

`docs/design/cocoonmate-visual-asset-prompts-v1.md` is the source of generation prompts. Fetal assets remain `medical review pending`; retain the code-native fallback until the release gate is approved.
