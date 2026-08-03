# bb287 full UI/UX parity ledger

Reference commit: `bb28701971cb2d43cde5acb5d50ef679dded534f`

Current `main` baseline at audit start: `fd6ec548b963070d981f25d31065fe113eb75e99`

Active audit branch: `feat/bb287-parity-completion`

Draft pull request: `#42`

Verified code-and-build checkpoint: `e07c09039c2e33e4f64013047799c32abfe1c18f`

Current package version: `0.8.0-beta.4+11`

> This ledger was reopened after founder review. The previous revision marked many
> source-level items complete before screenshot comparison and physical-device
> verification. A green build or an existing route is not sufficient evidence of
> visual parity.

The detailed page and interaction inventory is maintained in:

- `docs/ui/BB287_ROUTE_MATRIX.md`

## Completion policy

A page can be marked complete only when all applicable evidence exists:

- [ ] reference file and current file recorded;
- [ ] widget hierarchy, spacing, typography, colors, assets and navigation reviewed;
- [ ] loading, empty, error and retry states reviewed;
- [ ] Persian RTL and English LTR reviewed;
- [ ] large text scale and small Android screen reviewed;
- [ ] regression test added or a reason recorded when automation is impractical;
- [ ] CI passes on the exact head commit;
- [ ] physical-device result recorded for interactive/layout-sensitive behavior;
- [ ] screenshot evidence attached to the exact commit.

No route is currently labelled `COMPLETE` under this stricter definition.

## Reference assets and identity

### Verified in source, package declarations and checkpoint APKs

- [x] WellMate uses the green/mint visual identity.
- [x] CareMate uses the light-blue visual identity.
- [x] Android launcher resources resolve for both applications at standard densities.
- [x] Web favicon and standard/maskable icons exist for both applications.
- [x] Product logo, Vazir font and Flutter asset manifest are packaged inside both checkpoint APKs.
- [x] Runtime source scan rejects known mock-health-data sources.

### Evidence still required

- [ ] compare launcher rendering on at least two physical Android launchers;
- [ ] capture header/logo/avatar screenshots at target device dimensions;
- [ ] repeat archive inspection on the final release-candidate commit and release signing identity.

## Video evidence reviewed

The four available user-journey videos were reviewed as complementary evidence:

- `Media1.mp4`: Home, countdown, today schedule and Calendar;
- `Media2.mp4`: caregivers, relationships and access settings;
- `Media3.mp4`: treatment list and treatment creation/scheduling;
- `Media4.mp4`: Profile, Subscription and Profile Switching.

The videos themselves and test-account credentials are not committed to the repository.

## WellMate audit state

| Area | Source/backend state | Visual state | Device state | Result |
|---|---|---|---|---|
| Authentication | shared real Supabase Auth gate | pending comparison | pending | open |
| Home/header/greeting | live current-user and dose data | pending comparison | pending | open |
| Active treatment/countdown | live occurrence and adherence APIs | pending all states | pending | open |
| Today schedule | live occurrence data and reporting | pending comparison | pending | open |
| Calendar | live occurrence data | pending Jalali/RTL review | pending | open |
| Treatment list/details | live treatment plans | pending comparison | pending | open |
| Add treatment — medicine/schedule/review | live medication and plan creation; multiple times and explicit timezone supported | Persian small-screen regression passed; full reference comparison pending | physical keyboard/device pending | open |
| Profile and menu destinations | live identity; unsupported writes disabled; version synchronized | pending comparison | pending | open |
| Caregiver invitation/relationship | live invitation and revoke APIs | pending comparison | two-account E2E pending | open |
| Notifications/reminders | local reminder layer plus live dose state | pending comparison | permission/OEM tests pending | open |
| Referral/support/subscription | full destinations retained; mutations disabled | pending comparison | pending | open |
| Settings/logout | local locale/text-scale and real sign-out | pending comparison | pending | open |

## CareMate audit state

| Area | Source/backend state | Visual state | Device state | Result |
|---|---|---|---|---|
| Authentication | shared real Supabase Auth gate | pending comparison | pending | open |
| Dashboard/header | live current user, relationships and recipient doses | pending comparison | pending | open |
| Patient selector/profile switching | live active relationships | pending comparison | pending isolation test | open |
| Invitation acceptance | live consented acceptance | pending comparison | two-account E2E pending | open |
| Treatment queue/summary/list | live recipient dose occurrences | pending all states | pending | open |
| Alerts | live missed/skipped dose states | pending comparison | pending | open |
| Calendar | live consent-scoped recipient data | pending Jalali/RTL review | pending | open |
| Profile and menu destinations | live caregiver identity; unsupported writes disabled; version synchronized | pending comparison | pending | open |
| Family/health preview pages | dedicated coming-soon pages; no fabricated health values | pending comparison | pending | open |
| Relationship revoke/logout | real API revoke and Auth sign-out | pending comparison | E2E/device pending | open |

## Corrections completed on PR #42

- [x] Added an explicit page-by-page and button-by-button route/evidence matrix.
- [x] Reopened visual parity instead of inheriting the previous completion claims.
- [x] Corrected stale displayed versions in both profiles and added pubspec-alignment regression tests.
- [x] Added semantic button labels, selected state and minimum 48dp touch height to both floating bottom navigation bars.
- [x] Added small-screen and 1.5x text-scale widget tests for both bottom navigation bars.
- [x] Added deterministic multiple-time treatment schedules with duplicate removal and stable ordering.
- [x] Added an explicit treatment timezone initialized from the authenticated profile.
- [x] Added Persian RTL, 320×640 and 1.5x text-scale regression coverage for treatment scheduling.
- [x] Added PR Android APK builds plus manifest, 401/health/readiness, signing, packaged asset and SHA-256 inspection.
- [x] Kept PR #42 in Draft state.

## Confirmed remaining functional/product gaps

- [ ] Automatic delivery of the caregiver invitation token is not implemented; the current UI only supports secure manual copy/share.
- [ ] The current live two-account invitation → acceptance → recipient read → revoke journey has not been re-executed for this candidate.
- [ ] Notification permission recovery, reboot, app update, timezone change and OEM background behavior remain unverified on devices.
- [ ] Full screenshot evidence for every route is still missing.
- [ ] English/LTR parity of newly expanded treatment scheduling remains open because visible copy is currently Persian-first.

## Automated checkpoint — exact head `e07c09039c2e33e4f64013047799c32abfe1c18f`

GitHub Actions Flutter run `#179` / run id `30796716187` completed successfully:

- [x] reference asset and runtime mock-data gate;
- [x] shared `lifemate_client` pub get, analyze and tests;
- [x] WellMate pub get, analyze, tests and Web release build;
- [x] CareMate pub get, analyze, tests and Web release build;
- [x] live API health and database readiness;
- [x] unauthenticated `/api/v1/me` boundary returned 401;
- [x] WellMate Android release-mode APK build;
- [x] CareMate Android release-mode APK build;
- [x] package/version badging and Internet permission inspection;
- [x] APK Signature Scheme v2 verification;
- [x] Flutter asset manifest, product logo, Vazir font and launcher resource inspection;
- [x] SHA-256 calculation.

Checkpoint APK evidence:

| App | Size | SHA-256 | Signing note |
|---|---:|---|---|
| WellMate | 61,303,867 bytes | `c414421ebdcd510747a5995a2689f037c8c1e317300424346b16496b78ab1642` | valid v2 signature using Android Debug certificate; internal checkpoint only |
| CareMate | 57,383,399 bytes | `5b88ec8669ca98b4dd1af467d8e6d4d1dda13cab74d5a48eb9fabe4737dda3d9` | valid v2 signature using Android Debug certificate; internal checkpoint only |

These APKs are not release candidates and must not be represented as production-signed artifacts.

## Backend and security release boundary

The UI parity PR does not close the existing stable-beta security gates.
Live inspection still confirms:

- the Edge database connection currently runs as the `postgres` role;
- that role has `BYPASSRLS`, `CREATEROLE` and `CREATEDB`;
- all LifeMate healthcare tables currently have RLS disabled and `FORCE ROW LEVEL SECURITY` disabled;
- Supabase leaked-password protection is disabled.

These are release blockers tracked separately in issue `#16` and must be fixed and retested before onboarding real families. Enabling RLS without first replacing the runtime role would not provide effective defense in depth.

## Remaining manual acceptance boundary

- [ ] install the final candidate on representative physical Android devices;
- [ ] inspect every route at real device dimensions and text scale;
- [ ] execute the real two-account patient/caregiver journey without exposing credentials;
- [ ] verify wrong-account denial, unrelated-user denial and immediate post-revocation denial;
- [ ] verify reminder permission, delivery and recovery under target OEM restrictions;
- [ ] attach screenshot evidence and device notes to the exact candidate commit;
- [ ] configure and verify a non-debug release signing identity;
- [ ] repeat final APK archive and SHA-256 verification after all source changes.

## Release decision

Status: **NOT READY FOR RELEASE CANDIDATE**.

Reasons: visual evidence is incomplete, physical QA is incomplete, current two-account E2E evidence is incomplete, notification reliability is unverified, production signing is not configured, and P0 database hardening remains open.
