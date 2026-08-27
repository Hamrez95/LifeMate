# Legal / Privacy client QA evidence — 2026-08-27

Issue: #504

## Implemented source evidence

- Shared authenticated client reads canonical registration status, submits the exact current legal document id/hash set, and reads/mutates optional privacy preferences.
- Registration composition is shared through `LifeMateAccountOnboardingGate`, so WellMate and CareMate cannot reach the authenticated product shell until minimal account onboarding and the independent current legal gate are satisfied.
- Required legal checkboxes are not pre-selected.
- Optional promotional SMS/Push/Email, Research and Personalization preferences remain separate from mandatory acceptance and default off in the canonical catalog.
- Profile surfaces in both products inherit one shared `Privacy & preferences` entry point.
- Transactional, security and care-reminder communications are explicitly described as separate from marketing preferences.
- Client/UI tests cover current-version parsing, idempotent acceptance, fail-closed missing sessions, non-prechecked mandatory acceptance and independent optional preference mutation.
- Source contract verifies reuse of `consent.data_use_consents` and the self-only legal acceptance invariant.

## CI

`.github/workflows/onboarding-v3-integration.yml` now analyzes/tests both shared packages and includes the legal/privacy source verifier. GitHub-hosted runners have recently failed before step execution (`runner_id=0`, empty steps); that infrastructure condition must not be represented as a product pass.

## External/manual evidence

No human legal approval is claimed here. #214 remains the governance/legal approval gate. Physical-device visual/accessibility QA remains separate from source completion.
