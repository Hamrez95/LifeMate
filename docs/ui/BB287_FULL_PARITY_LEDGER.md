# bb287 full UI/UX parity ledger

Reference commit: `bb28701971cb2d43cde5acb5d50ef679dded534f`

Target verification version: `0.8.0-beta.4+11`

## Exact visual binaries restored
- [x] `caremate/assets/images/Caregiver.png` — exact reference blob `faf717eda6099c8d2c50f270153aa02b413d7722`
- [x] CareMate Android launcher icons: mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi
- [x] CareMate favicon and all standard/maskable web icons
- [x] WellMate Android launcher icons: mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi
- [x] WellMate favicon and all standard/maskable web icons
- [x] `CareMateWithoutBack.png`, `Caregiver.png`, `WellMateWithoutBack.png`, `mother_avatar.png`, and WellMate medicine icons are explicitly declared and verified inside release APKs

## CareMate visual and navigation review
- [x] `caremate/lib/main.dart` — reference theme, Persian/English localization, and logo behavior retained; authentication is added outside a nested authenticated Navigator so every pushed route keeps `LifeMateApiClient` in scope
- [x] `caremate/lib/screens/dashboard_screen.dart` — reference hierarchy retained: header, care recipient/treatment queue, paired pastel feature cards, daily progress summary, medicine list, and floating bottom navigation; mock pregnancy/baby values are not presented as live health data
- [x] `caremate/lib/widgets/custom_app_header.dart` — centered CareMate logo, notification surface/dot, caregiver avatar, profile navigation, and logout retained with live alert state
- [x] Calendar page is connected to active care relationships and real patient dose occurrences
- [x] Profile page retains the original pastel card/menu hierarchy and uses live caregiver identity
- [x] Profile, calendar, account, notification, referral, support, subscription, profile switching, treatment-view, and family-care destinations are real routes rather than snackbars
- [x] Unsupported health/family features retain dedicated pages and visibly disabled `در دست توسعه` controls without fabricated health data
- [x] CareMate profile route regression test opens the page through Navigator and verifies API Provider scope, preventing the release gray-screen regression

## WellMate visual and navigation review
- [x] `wellmate/lib/main.dart` — reference theme retained; authentication is wrapped around a nested Navigator so Profile and every pushed destination retain `LifeMateApiClient`
- [x] `wellmate/lib/core/widgets/wellmate_app_header.dart` — reference layout, logo, avatar, notification dot, and missed-dose sheet retained with declared asset paths
- [x] `wellmate/lib/screens/home/active_treatment_card.dart` — reference dimensions, spacing, typography, progress ring, countdown, medicine icon, and three-action composition retained; taken/skipped/edit callbacks use live state
- [x] `wellmate/lib/screens/home/home_screen.dart` — reference scaffold, header, IndexedStack, pastel background, and four-item bottom navigation retained
- [x] `wellmate/lib/screens/home/home_screen_content.dart` — greeting, next-dose treatment card, countdown, rounded white daily schedule panel, schedule cards, loading/error/empty states, and live API reporting retained
- [x] Next-dose lookup covers the coming seven days so the countdown is not lost when today has no remaining dose
- [x] No-treatment and no-next-dose states retain a visible timer surface (`تایمر درمان آماده است` / `--:--`) instead of removing the home timer area
- [x] `wellmate/lib/screens/treatments/add_treatment_screen.dart` restores the multi-step tabbed flow: `دارو`, `برنامه`, and `مرور`
- [x] Medication name, strength, form, dose, time, daily/selected weekdays, start date, optional end date, instructions, and final review are connected to `createMedication` and `createTreatmentPlan`
- [x] Treatment list and dedicated treatment detail routes use live treatment plans; unsupported update/delete operations are not fabricated
- [x] Profile restores the reference avatar (`mother_avatar.png`), camera badge, subscription card, grouped pastel menu, settings dialog, account destinations, caregiver access, and logout while using live identity/contact
- [x] Personal information, health record, caregivers, notifications, referral, support, and subscription have dedicated original-style routes; unsupported mutations remain explicitly disabled
- [x] Empty schedule copy distinguishes no treatment, no dose today, and all doses completed

## Device-regression fixes prompted by beta.3
- [x] Fixed gray Profile screens in both apps by keeping the API Provider above all pushed Navigator routes
- [x] Added regression tests that navigate to both Profile screens and require successful rendering with live-data contracts
- [x] Restored the WellMate profile avatar/camera composition and added assertions for the exact declared asset path
- [x] Restored and tested the three treatment tabs
- [x] Added deterministic countdown tests plus source contracts requiring both live and empty timer states and the circular progress ring
- [x] Removed temporary one-shot repair workflows after use

## Automated acceptance gates
- [x] Exact bb287 visual binary comparison passes
- [x] Runtime source scan rejects `AppMockData`/`MockData` health-data usage
- [x] Shared LifeMate client analyze and tests pass
- [x] WellMate analyze, unit/widget regression tests, and release Web build pass
- [x] CareMate analyze, unit/widget regression tests, and release Web build pass
- [x] Live API health reports `status=ok` and `database=ready`
- [x] Protected `/api/v1/me` returns HTTP 401 without authentication
- [x] WellMate and CareMate release Android APK builds pass and declare `android.permission.INTERNET`
- [x] Required logos, avatars, medicine icon, and localization files are present inside the generated APK archives

## Remaining manual acceptance boundary
- [ ] Install `0.8.0-beta.4+11` on physical Android devices and visually inspect every route at the device's actual text scale and screen dimensions
- [ ] Execute the real two-account WellMate invitation → CareMate acceptance flow on physical devices
- [ ] Confirm notification permission/reminder behavior under the target OEM's background restrictions

## Acceptance rules
- Every original page and navigation destination remains present.
- Backend-supported actions are live and persisted.
- Unsupported actions open a dedicated destination and are visibly disabled or marked `در دست توسعه`.
- No mock health information is presented as live user data.
- Flutter analyze, tests, web builds, Android builds, and live API boundary checks must pass before an APK is shared.
