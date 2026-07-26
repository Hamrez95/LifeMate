# Android beta execution plan

## Remaining delivery path

### v0.4 — adherence engine
- Persist bounded deterministic dose occurrences
- Append-only adherence events with idempotency keys
- Patient-owned range and action APIs
- Cross-user isolation, DST, retry, and concurrency tests
- Canonical migration and Supabase deployment

### v0.5 — Flutter production integration
- Add Supabase authentication to WellMate and CareMate
- Add shared API client configuration and token refresh
- Replace hardcoded/mock core flows with LifeMate.Api
- WellMate: treatment list, today's doses, taken/skipped actions, caregiver invitations
- CareMate: relationships and authorized patient adherence status
- Preserve unfinished ecosystem modules as honest `به‌زودی` screens
- Add loading, empty, validation, offline, retry, and session-expiry states

### v0.6 — reminders and observability
- Reliable local Android reminders in WellMate
- Device registration and controlled push path for CareMate
- Minimal crash reporting and privacy-safe product telemetry
- No paid notification provider before beta evidence

### v0.7 — Android beta release
- Flutter analyze and tests for both apps
- Real-device smoke tests
- RTL, text scaling, contrast, touch target, and accessibility review
- Stable application IDs, versioning, icons, and release configuration
- CI build of unsigned/internal-test APKs
- Founder-owned release keystores for signed APK/AAB
- APK artifacts for WellMate and CareMate

## Release stop conditions
Do not distribute the beta when any P0 remains, authentication/data isolation is unverified, reminders are unreliable, production secrets are embedded, or Android release artifacts are not reproducible.
