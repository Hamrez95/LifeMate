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

### 1. Visual QA for the just-polished forms — next

- Render Symptoms, Measurements, Medication, Appointments, Appointment form/detail, Reminders and Education in FA RTL and EN LTR.
- Add stable goldens only for the populated reference screens; verify 390×844, small phone and text scale 1.5.
- Fix directional icons, clipped content and touch targets discovered by those renders.
- Issue handling: comment on #792, #793, #794, #795 and #800 after the PR is merged. Do not close: adapter/reconciliation work remains.

### 2. Onboarding and navigation shell

- Polish the activation journey, back/navigation direction, review/error states and reduced-motion behaviour against the supplied mobile mockups.
- Audit the Cocoon shell against the new LifeMate Shell mount; preserve product-owned routes and avoid a competing root navigation model.
- Issue handling: comment on #788 and #806 after merge. Do not close #788 until activation adapter and entitlement/session cases are complete.

### 3. Records and scoped sharing

- Bind the existing Records UI to the canonical paginated read-model adapter once its Flutter client binding exists; keep cached/partial/error UI honest.
- Design caregiver/partner surfaces only around the Circle consent-safe contract and explicit scope states.
- Issue handling: comment on #796, #798 and #799 after merge. Close only a narrow issue whose server contract, UI, tests and revocation paths are all complete.

### 4. Home and Week Detail final art pass

- Integrate approved production assets, replace code-native fallback only after fetal release-gate approval, and re-run RTL/LTR goldens.
- Add subtle reduce-motion-safe transitions for hero/week changes and state transitions.
- Issue handling: do not close the fetal-art release gate until medical review, asset manifest and device QA are complete.

### 5. Final release QA

- Execute full widget/golden suite, physical Android QA, accessibility semantics and contrast pass.
- Resolve only visual defects in this stream; create or update backend handoff comments for genuine adapter gaps.

## Backend handoff rules

- Flutter must consume the reviewed API/client adapters only; it must not add a second store, scheduler, outbox, healthcare schema or clinical evaluator.
- Pregnancy week/day is derived from approved dating, never a mutable UI field.
- Clinical copy, symptom catalog and safety levels remain host-supplied and versioned.
- UI callbacks must expose `loading`, `offline cached`, `queued`, `confirmed`, `partial`, `unavailable` and `error` honestly; queued is not server confirmation.
- A frontend task can be marked complete only after RTL/LTR, large text, semantics, overflow checks and stable widget/golden coverage. A backend issue remains open until its authorized adapter, reconciliation and tests exist.

## Asset dependency

`docs/design/cocoonmate-visual-asset-prompts-v1.md` is the source of generation prompts. Fetal assets remain `medical review pending`; retain the code-native fallback until the release gate is approved.
