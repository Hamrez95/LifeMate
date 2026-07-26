# Android release gates

## Build and identity
- Final application IDs are documented and stable.
- Version code and version name are incremented predictably.
- Release keystore is stored outside Git and backed up securely by the founder.
- APK and AAB are generated from a reproducible release workflow.

## Functional
- Authentication, bootstrap, medication schedule, adherence recording, caregiver invitation/acceptance/revocation, and caregiver read paths work against the production API.
- No core production flow depends on hardcoded or demo data.
- Coming-soon capabilities are clearly labelled and cannot collect unsupported health data.

## Security and privacy
- Cross-user isolation tests pass.
- Consent and revocation are available in-app.
- Account deletion and data handling are documented.
- No production secret is embedded in the APK beyond publishable client configuration.

## Quality
- No open P0 or launch-blocking P1 defects.
- Crash, loading, empty, validation, offline, and retry states have been tested.
- RTL, text scaling, contrast, touch targets, and screen-reader labels have been reviewed.
- Core flows are tested on multiple real Android devices, including at least one lower/mid-range device.

## Operations
- Backend health checks are green.
- Database migration is applied and verified.
- Backup/export and rollback procedures exist.
- Release notes and known limitations are written.
