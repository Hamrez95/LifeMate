# bb287 full UI/UX parity ledger

Reference commit: `bb28701971cb2d43cde5acb5d50ef679dded534f`

## Exact visual binaries restored
- [x] `caremate/android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- [x] `caremate/android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- [x] `caremate/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- [x] `caremate/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- [x] `caremate/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- [x] `caremate/web/favicon.png`
- [x] `caremate/web/icons/Icon-192.png`
- [x] `caremate/web/icons/Icon-512.png`
- [x] `caremate/web/icons/Icon-maskable-192.png`
- [x] `caremate/web/icons/Icon-maskable-512.png`
- [x] `wellmate/android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- [x] `wellmate/android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- [x] `wellmate/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- [x] `wellmate/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- [x] `wellmate/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- [x] `wellmate/web/favicon.png`
- [x] `wellmate/web/icons/Icon-192.png`
- [x] `wellmate/web/icons/Icon-512.png`
- [x] `wellmate/web/icons/Icon-maskable-192.png`
- [x] `wellmate/web/icons/Icon-maskable-512.png`

## UI source files changed after the reference and requiring integration review
- [ ] `caremate/lib/main.dart` — retain authentication shell; verify exact theme and logo behavior
- [ ] `caremate/lib/screens/dashboard_screen.dart` — restore exact visual hierarchy while mapping live API data
- [ ] `caremate/lib/widgets/custom_app_header.dart` — restore exact header visuals without mock alerts
- [ ] `wellmate/lib/main.dart` — retain authentication shell and reference theme
- [x] `wellmate/lib/core/widgets/wellmate_app_header.dart` — reference layout preserved; only invalid legacy asset paths were normalized to declared Flutter asset paths, while live missed-dose and notification state remains connected
- [x] `wellmate/lib/screens/home/active_treatment_card.dart` — exact reference dimensions, spacing, typography, progress ring, icon treatment, and three-action composition preserved; real taken, skipped, edit, and submitting states are wired without mock health data
- [x] `wellmate/lib/screens/home/home_screen.dart` — exact reference scaffold, header, IndexedStack, background, and bottom-navigation composition preserved; the two former placeholder destinations now open live Treatments and Add Treatment screens and refresh Home after creation
- [x] `wellmate/lib/screens/home/home_screen_content.dart` — reference page hierarchy, spacing, active-treatment placement, rounded schedule panel, schedule-card composition, loading treatment, and ordering are preserved; mock “مامان جون” filtering was removed and the screen now uses the authenticated profile, live treatment plans, live dose occurrences, persisted taken/skipped reporting, reminder synchronization, retry UI, and no fabricated health records
- [x] `wellmate/lib/screens/profile/profile_screen.dart` — reference card hierarchy, pastel visual language, typography, subscription surface, menu grouping, settings dialog, and logout surface are preserved; identity and contact now come from the authenticated API profile, language/text-size controls remain functional, caregiver access navigates to a real connected screen, logout is real, and unsupported destinations remain visible with disabled «به‌زودی» state

## QA findings retained for follow-up
- [ ] WellMate empty schedule copy must distinguish “no treatment plan/doses exist” from “all doses completed”; current fallback can imply completion when the API returns an empty list.
- [ ] WellMate active-treatment edit action still opens a clearly labeled coming-soon message until the update-treatment API/UI route is wired.
- [ ] Profile personal information, health record, referral, support, notification center, and subscription purchase require dedicated original-style destination pages rather than only disabled tiles/snackbars.
- [ ] Verify every image asset reference against `pubspec.yaml`; legacy `../../assets/...` paths should be normalized only where required without changing visual binaries.

## Verified build checkpoint
- [x] Shared client analyze and tests pass.
- [x] WellMate analyze, tests, release Web build, and release Android APK pass.
- [x] CareMate analyze, tests, release Web build, and release Android APK pass.
- [x] Live API health reports `status=ok` and `database=ready`.
- [x] Protected `/api/v1/me` boundary returns HTTP 401 without authentication.
- [x] Both release APKs declare `android.permission.INTERNET`.
- [x] Commit `fdbc346ad97c8ab3f2f211016baa26a43d85d253` passed both `flutter` and `internal-beta-release` workflows.
- [x] Commit `89b4bc838bbb41fa9e12755ff3fce2b839f28709` passed both `flutter` and `internal-beta-release` workflows after the WellMate home parity audit.

## Acceptance rules
- Every original page and navigation destination remains present.
- Backend-supported actions are live and persisted.
- Unsupported actions open their original destination but are visibly disabled or marked «در دست توسعه».
- No mock health information is presented as live user data.
- Flutter analyze, tests, web builds, Android builds, and live API boundary checks must pass.
