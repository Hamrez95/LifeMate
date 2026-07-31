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
- [ ] `wellmate/lib/screens/home/home_screen_content.dart` — exact reference composition with live API data
- [ ] `wellmate/lib/screens/profile/profile_screen.dart` — exact reference profile composition with live account data

## Verified build checkpoint
- [x] Shared client analyze and tests pass.
- [x] WellMate analyze, tests, release Web build, and release Android APK pass.
- [x] CareMate analyze, tests, release Web build, and release Android APK pass.
- [x] Live API health reports `status=ok` and `database=ready`.
- [x] Protected `/api/v1/me` boundary returns HTTP 401 without authentication.
- [x] Both release APKs declare `android.permission.INTERNET`.
- [x] Commit `fdbc346ad97c8ab3f2f211016baa26a43d85d253` passed both `flutter` and `internal-beta-release` workflows.

## Acceptance rules
- Every original page and navigation destination remains present.
- Backend-supported actions are live and persisted.
- Unsupported actions open their original destination but are visibly disabled or marked «در دست توسعه».
- No mock health information is presented as live user data.
- Flutter analyze, tests, web builds, Android builds, and live API boundary checks must pass.
