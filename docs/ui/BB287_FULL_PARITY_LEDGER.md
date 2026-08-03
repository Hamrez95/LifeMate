# bb287 full UI/UX parity ledger

Reference commit: `bb28701971cb2d43cde5acb5d50ef679dded534f`

Current `main` baseline at audit start: `fd6ec548b963070d981f25d31065fe113eb75e99`

Active audit branch: `feat/bb287-parity-completion`

Draft pull request: `#42`

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

### Verified in source and package declarations

- [x] WellMate uses the green/mint visual identity.
- [x] CareMate uses the light-blue visual identity.
- [x] Android launcher icons exist for both applications at standard densities.
- [x] Web favicon and standard/maskable icons exist for both applications.
- [x] Core logos, avatars and medicine imagery are declared in Flutter assets.
- [x] Runtime source scan rejects known mock-health-data sources.

### Evidence still required

- [ ] inspect the exact assets inside the final release-candidate APK archives;
- [ ] compare launcher rendering on at least two Android launchers;
- [ ] capture header/logo/avatar screenshots at target device dimensions.

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
| Add treatment — medicine/schedule/review | live medication and plan creation | pending comparison | pending keyboard/overflow | open |
| Profile and menu destinations | live identity; unsupported writes disabled | pending comparison | pending | open |
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
| Profile and menu destinations | live caregiver identity; unsupported writes disabled | pending comparison | pending | open |
| Family/health preview pages | dedicated coming-soon pages; no fabricated health values | pending comparison | pending | open |
| Relationship revoke/logout | real API revoke and Auth sign-out | pending comparison | E2E/device pending | open |

## Corrections completed on PR #42

- [x] Added an explicit page-by-page and button-by-button route/evidence matrix.
- [x] Reopened visual parity instead of inheriting the previous completion claims.
- [x] Corrected CareMate's stale displayed version and added a pubspec-alignment regression test.
- [x] Added semantic button labels, selected state and minimum 48dp touch height to both floating bottom navigation bars.
- [x] Added small-screen and 1.5x text-scale widget tests for both bottom navigation bars.
- [x] Kept PR #42 in Draft state.

## Confirmed functional/product gaps

- [ ] WellMate profile still contains a stale hard-coded version label and must use a single version source.
- [ ] Treatment creation currently supports only one local time per treatment plan.
- [ ] Treatment creation currently fixes the timezone to `Asia/Tehran` instead of making the selected/profile timezone explicit.
- [ ] Automatic delivery of the caregiver invitation token is not implemented; the current UI only supports secure manual copy/share.
- [ ] The current live two-account invitation → acceptance → recipient read → revoke journey has not been re-executed for this candidate.
- [ ] Notification permission recovery, reboot, app update, timezone change and OEM background behavior remain unverified on devices.
- [ ] Full screenshot evidence for every route is still missing.

## Automated gates

### Last verified checkpoint before the latest navigation changes

- [x] shared client analyze/tests passed;
- [x] WellMate analyze/tests/Web release build passed;
- [x] CareMate analyze/tests/Web release build passed;
- [x] mock-health-data source gate passed;
- [x] internal release policy workflow passed/skipped artifact publication outside the protected release path.

### Current head

- [ ] wait for the Flutter workflow on the exact latest head and record its result here;
- [ ] Android APK builds are intentionally not treated as a release artifact on ordinary feature-branch pushes.

## Backend and security release boundary

The UI parity PR does not close the existing stable-beta security gates.
Live inspection still confirms:

- the Edge database connection currently runs as the `postgres` role;
- that role has `BYPASSRLS`, `CREATEROLE` and `CREATEDB`;
- all LifeMate healthcare tables currently have RLS disabled and `FORCE ROW LEVEL SECURITY` disabled;
- Supabase leaked-password protection is disabled.

These are release blockers tracked separately and must be fixed and retested before onboarding real families. Enabling RLS without first replacing the runtime role would not provide effective defense in depth.

## Remaining manual acceptance boundary

- [ ] install the final candidate on representative physical Android devices;
- [ ] inspect every route at real device dimensions and text scale;
- [ ] execute the real two-account patient/caregiver journey without exposing credentials;
- [ ] verify wrong-account denial, unrelated-user denial and immediate post-revocation denial;
- [ ] verify reminder permission, delivery and recovery under target OEM restrictions;
- [ ] attach screenshot evidence and device notes to the exact candidate commit;
- [ ] confirm final APK assets, manifest, signing identity, installability and SHA-256.

## Release decision

Status: **NOT READY FOR RELEASE CANDIDATE**.

Reasons: visual evidence is incomplete, physical QA is incomplete, current two-account E2E evidence is incomplete, notification reliability is unverified, and P0 database hardening remains open.
