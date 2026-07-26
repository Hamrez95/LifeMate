# LifeMate Release Critic Gates

Every production feature must pass these gates before release.

## Product critic
- Solves a documented user problem in the patient-caregiver core loop.
- Has a measurable success metric and a clear non-goal.
- A simpler alternative was considered.
- Future-scope capabilities are preserved as honest `Coming soon` surfaces, not fake active actions.

## Architecture and security critic
- Core health data is read and mutated only through `LifeMate.Api`.
- Authorization is derived from the authenticated subject and care relationship, never from a client-supplied user id.
- Cross-user isolation has integration tests.
- Sensitive state changes are audited.
- No secret, token, OTP, or connection string is committed.

## UI/UX critic
- One clear primary action per screen.
- Loading, empty, offline, validation, success, and error states exist.
- RTL, Persian copy, text scaling, contrast, touch targets, and screen-reader labels are reviewed.
- Elderly users are not required to discover hidden gestures.
- Inactive features are labelled `به‌زودی` and do not look operational.

## Visual critic
- WellMate and CareMate retain their distinct identities while sharing typography, spacing, radius, iconography, and component behaviour.
- Red is reserved for meaningful warnings.
- Decorative elements must not reduce readability or contrast.

## Reliability and performance critic
- Duplicate requests are safe where appropriate.
- Date/time handling persists UTC and presents in the user's timezone.
- Mobile startup, list rendering, network retries, and notification delivery are measured on real Android devices.
- No polling loop is accepted without an explicit reason and backoff policy.

## Real-user test critic
- Internal alpha passes before inviting external families.
- The core flow is tested by at least five older adults or patients and five caregivers.
- Observed behaviour outranks stated preference.
- Findings are recorded with severity, reproduction steps, and product implication.

## Privacy and trust critic
- Consent is explicit, understandable, versioned, and revocable.
- The patient can see and revoke caregiver access.
- Copy does not imply diagnosis, prescription, emergency monitoring, or guaranteed medication intake.
- A recorded `taken` state means the user reported it as taken.

## Release gate
A release candidate is blocked by any open P0, failing CI, untested migration, broken account deletion/revocation path, exposed secret, or unverified Android signing configuration.
