# LifeMate Onboarding V3 — Candidate QA Gate

Candidate date: 2026-08-27
Scope: #522–#527

## Automated gate

The repository now has a dedicated `onboarding-v3-integration` workflow. It verifies the cross-product canonical integration contract, the shared `lifemate_ui` onboarding component tests, responsive/accessibility matrix tests, WellMate first-value and Women Health activation contracts, and CareMate relationship/consent contracts.

Responsive matrix covered by widget tests:

- 390x844 reference viewport;
- 360x760;
- 360x640;
- 320x568;
- safe-area top and gesture-navigation bottom insets;
- keyboard/IME inset with fixed CTA and no scroll wrapper;
- Persian RTL and English LTR;
- explicit LTR isolation for phone-like entry;
- large text scaling;
- 48dp minimum interactive targets;
- selected-state indication beyond color alone.

Cross-product source contract verifies:

- WellMate and CareMate use the same shared V3 authentication and account-onboarding presentation;
- account Display Name is persisted through canonical profile/Person contracts and intent remains presentation metadata;
- WellMate first value opens the real treatment form and keeps native notification permission contextual;
- Women Health activation writes the canonical Women Calendar profile, uses the existing Jalali-aware picker, and rejects private/fertility inference inputs;
- CareMate relationship hint is not authorization, pairing uses the canonical invitation acceptance path, pending state discloses no health data, fertility scopes are independent/fail-closed, and active relationship checks remain authoritative;
- app-specific flows consume `LifeMateOnboardingScaffold` rather than defining local scaffold forks.

## Database/runtime evidence

The #524 WellMate first-value migrations and #525 Women Health activation metadata migration were applied to the LifeMate Supabase project during implementation. Existing WellMate accounts were explicitly backfilled to avoid unexpected first-value onboarding after upgrade; new accounts retain unresolved first-value state until they complete or skip it. Women Health metadata was added to the existing canonical profile rather than creating a second profile.

## CI infrastructure status

GitHub-hosted workflow execution is currently not usable as acceptance evidence. Recent Flutter/Edge runs for these PRs failed before any workflow step started (`runner_id=0`, empty step list). This is recorded as CI infrastructure failure, not a passing or failing product test result. The new workflow is committed so the gate will execute automatically when runners are available.

## Physical-device QA — required before closing #527

Physical-device QA has **not** been executed by the coding agent and must not be marked complete without real device evidence. Run the exact candidate on a representative Android device and record results for:

1. fresh signup and restored existing session in Persian and English;
2. keyboard open/close on email, phone, OTP and manual CareMate invitation entry;
3. status bar, gesture navigation and lower-height viewport behavior;
4. WellMate: create first medication, verify Home/calendar/reminder behavior, deny/allow notification permission, relaunch;
5. Women Health: regular, irregular, unknown and unsure flows, Jalali date boundary, relaunch and edit through existing management;
6. CareMate: valid QR/manual invitation, invalid/expired/self/replayed invitation, pending state, exact accepted scopes, revoke and reconnect;
7. large system font and accessibility/TalkBack focus order;
8. offline/retry transitions without raw backend/provider errors or stale protected data.

Record device model, Android version, app build SHA and any screenshots/logs used as evidence. #527 should remain open until this physical-device section is completed and no P0/P1 onboarding defect remains.
