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
- [ ] `wellmate/lib/core/widgets/wellmate_app_header.dart` — exact reference layout with live missed-dose state
- [ ] `wellmate/lib/screens/home/active_treatment_card.dart` — exact reference card with live actions
- [ ] `wellmate/lib/screens/home/home_screen.dart` — all original destinations remain navigable
- [ ] `wellmate/lib/screens/home/home_screen_content.dart` — exact reference composition with live API data
- [ ] `wellmate/lib/screens/profile/profile_screen.dart` — exact reference profile composition with live account data

## Acceptance rules
- Every original page and navigation destination remains present.
- Backend-supported actions are live and persisted.
- Unsupported actions open their original destination but are visibly disabled or marked «در دست توسعه».
- No mock health information is presented as live user data.
- Flutter analyze, tests, web builds, Android builds, and live API boundary checks must pass.
