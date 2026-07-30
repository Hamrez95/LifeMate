# LifeMate version plan

## v0.1 — Foundation
Status: complete

- ASP.NET Core modular monolith
- PostgreSQL / EF Core baseline
- User bootstrap and profile
- Privacy-consent foundation
- Audit log
- JWT validation foundation
- Health checks
- Green backend CI

## v0.2 — Care relationships
Status: complete

- Invitation creation and expiry
- Acceptance and rejection
- Patient-caregiver relationship
- Explicit consent and revocation
- Participant-only authorization
- Audit trail and abuse/rate-limit protections

## v0.3 — Treatment management
Status: complete
- Medication free-form entry
- Treatment plans
- Schedules
- Dose occurrences
- UTC persistence and timezone-safe presentation

## v0.4 — Adherence loop
Status: complete
- Taken, skipped, snoozed, missed
- Idempotent event recording
- Caregiver read model
- Missed-dose policy and audit trail

## v0.5 — Flutter production integration
Status: in progress
- Supabase Auth
- WellMate API integration
- CareMate API integration
- Remove mock/hardcoded production paths
- Complete loading/error/offline states
- Honest Coming soon surfaces

## v0.6 — Notifications and observability
Status: in progress
- Local reminders
- FCM device registration
- Missed-dose worker
- Crash reporting and minimal product analytics
- Backup/export runbook

## v0.7 — Android invite-only beta
Status: blocked on API hosting, CI billing, signing, and device verification
- Privacy, terms, and consent UX
- Accessibility and elderly-user review
- Android signing and versioning
- APK/AAB release artifacts
- 20–50 family beta
- Weekly interviews and cohort metrics

## v0.8 — Validation and monetization experiment
- Onboarding improvements based on observed behaviour
- Premium-value hypothesis
- Real payment experiment
- Multi-patient/multi-caregiver refinements where demand is proven

## v1.0 — Public release gate
- Core-loop retention demonstrated
- Notification reliability demonstrated
- No open P0/P1 launch blockers
- Tested backup/recovery and account deletion
- Support and incident-response process active
