# LifeMate 0.9.0-internal.5+16 Device-QA

This build is for internal physical-device testing only. It is not Stable, RC, or approved for public distribution.

## Candidate scope

- WellMate women-calendar pilot enabled only by the internal build flag.
- Per-relationship caregiver permission and immediate revoke behavior.
- CareMate women-calendar summary with owner-only private notes excluded.
- Persisted allow-listed profile avatars in WellMate and CareMate.
- Scoped medication notification synchronization and lock-screen privacy.

## Required physical checks

1. Notification permission UX on supported Android versions.
2. Exact-alarm fallback and scheduling behavior.
3. Lock-screen content minimization for both apps.
4. Notification resynchronization after reboot.
5. Notification resynchronization after timezone change.
6. Notification resynchronization after app update.
7. Women-calendar navigation on a small screen and large text scale.
8. Relationship and women-calendar permission revoke on two real accounts.
9. Avatar selection persistence after sign-out, sign-in, and app restart.

The APKs must target the non-production candidate API. No Production migration or Edge deployment is authorized by this checklist.
