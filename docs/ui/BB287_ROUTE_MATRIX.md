# bb287 route, interaction and evidence matrix

Reference commit: `bb28701971cb2d43cde5acb5d50ef679dded534f`

Audit branch: `feat/bb287-parity-completion`

Baseline currently on `main`: `fd6ec548b963070d981f25d31065fe113eb75e99`

## Why this matrix exists

PR #30 was merged while the only remaining items recorded in the previous ledger were manual/device checks. Founder review after that merge shows that visual parity must be re-opened and verified page by page. A green build or the existence of a route is not accepted as visual completion.

## Status vocabulary

- `ROUTE_PRESENT`: the destination can be found in current source.
- `LIVE_READ`: the screen reads authenticated API data.
- `LIVE_WRITE`: the action writes through the authenticated API.
- `COMING_SOON`: the full destination remains available, but unsupported mutation controls are disabled and clearly labelled.
- `SOURCE_REVIEW`: current and reference widget trees were compared in source.
- `VISUAL_PENDING`: screenshot/video comparison is still required.
- `DEVICE_PENDING`: physical Android verification is still required.
- `E2E_PENDING`: the real two-account flow has not been executed in the current release candidate.
- `BLOCKED`: a required dependency or secret is missing.

## Evidence rules

A row may become `COMPLETE` only when all applicable evidence exists:

1. current and reference file paths;
2. recorded source differences and the applied correction;
3. regression test or an explicit explanation why automation is not practical;
4. CI result on the exact head commit;
5. physical-device result when interaction, layout, notification or keyboard behavior is involved;
6. screenshot evidence at the target device size and text scale.

## WellMate page matrix

| Area | Current implementation | Backend state | Current audit state | Required evidence before complete |
|---|---|---|---|---|
| Sign in | shared `LifeMateSessionGate` | Supabase Auth | `ROUTE_PRESENT`, `VISUAL_PENDING`, `DEVICE_PENDING` | Persian/English, invalid credentials, keyboard, small Android |
| Sign up | shared `LifeMateSessionGate` | Supabase Auth | `ROUTE_PRESENT`, `VISUAL_PENDING`, `DEVICE_PENDING` | account creation and duplicate-email states |
| Forgot password | shared `LifeMateSessionGate` | Supabase Auth | `ROUTE_PRESENT`, `VISUAL_PENDING`, `DEVICE_PENDING` | email flow, deep-link/fallback behavior |
| Home shell/header | `home_screen.dart`, `wellmate_app_header.dart` | live identity/alerts | `SOURCE_REVIEW`, `VISUAL_PENDING`, `DEVICE_PENDING` | exact spacing, logo/avatar assets, notification action |
| Greeting | `home_screen_content.dart` | `getCurrentUser` | `LIVE_READ`, `VISUAL_PENDING` | empty name, long name, English/LTR |
| Active treatment/timer | `active_treatment_card.dart`, `home_screen_content.dart` | dose occurrences and adherence API | `LIVE_READ`, `LIVE_WRITE`, `VISUAL_PENDING`, `DEVICE_PENDING` | future dose, missed dose, no treatment, no dose today, all complete |
| Today schedule | `home_screen_content.dart`, `soft_schedule_card.dart` | dose occurrences | `LIVE_READ`, `LIVE_WRITE`, `VISUAL_PENDING` | taken/skipped/missed cards and retry |
| Calendar | `calendar_screen.dart`, `custom_table_calendar.dart` | dose occurrences | `LIVE_READ`, `VISUAL_PENDING`, `DEVICE_PENDING` | Jalali, month switch, selected day, empty/error |
| Treatment list | `treatments_screen.dart` | treatment plans | `LIVE_READ`, `VISUAL_PENDING` | list/empty/error/refresh and card parity |
| Treatment details | `_TreatmentDetailsScreen` in `treatments_screen.dart` | treatment plan data | `ROUTE_PRESENT`, `LIVE_READ`, `VISUAL_PENDING` | all fields, long text, unsupported mutations |
| Add treatment shell | `add_treatment_screen.dart` | create medication + plan | `LIVE_WRITE`, `VISUAL_PENDING`, `DEVICE_PENDING` | tab navigation, validation, keyboard, overflow |
| Medicine tab | `add_treatment_screen.dart` | medication create contract | `LIVE_WRITE`, `VISUAL_PENDING` | name, strength, form, dose and instructions |
| Schedule tab | `add_treatment_screen.dart` | plan/schedule create contract | `LIVE_WRITE`, `VISUAL_PENDING` | daily/selected weekdays, dates, timezone, multiple times |
| Review tab | `add_treatment_screen.dart` | preview before write | `ROUTE_PRESENT`, `VISUAL_PENDING` | summary must match persisted payload exactly |
| Profile | `profile_screen.dart` | current user | `LIVE_READ`, `VISUAL_PENDING`, `DEVICE_PENDING` | avatar/camera badge, menu groups, version label |
| Personal information | `profile_destination_screens.dart` | current user | `LIVE_READ`, `COMING_SOON`, `VISUAL_PENDING` | loading/error/retry and disabled edit |
| Health record | `profile_destination_screens.dart` | plans + doses only | `LIVE_READ`, `COMING_SOON`, `VISUAL_PENDING` | no fabricated vitals/labs/documents |
| Caregivers | `care_access_screen.dart` | invitations/relationships | `LIVE_READ`, `LIVE_WRITE`, `E2E_PENDING`, `DEVICE_PENDING` | two-account invite, accept, read and revoke |
| Invite caregiver | `care_access_screen.dart` | one-time invitation token | `LIVE_WRITE`, `E2E_PENDING` | exact email binding, one-time use, expiry, wrong-account denial |
| Notifications | `profile_destination_screens.dart` | current doses/local reminder layer | `LIVE_READ`, `DEVICE_PENDING` | permission denial/recovery, OEM background restrictions |
| Referral | `profile_destination_screens.dart` | unavailable | `COMING_SOON`, `VISUAL_PENDING` | full reference destination; no fake code |
| Support | `profile_destination_screens.dart` | unavailable | `COMING_SOON`, `VISUAL_PENDING` | full reference destination; disabled ticket action |
| Subscription | `profile_destination_screens.dart` | unavailable | `COMING_SOON`, `VISUAL_PENDING` | full reference destination; no fake purchase |
| Settings | dialog in `profile_screen.dart` | local settings | `ROUTE_PRESENT`, `DEVICE_PENDING` | locale/text scale persistence and large text |
| Logout | `LifeMateAuth.signOut` | Supabase Auth | `LIVE_WRITE`, `DEVICE_PENDING` | session cleared and authenticated routes inaccessible |

## CareMate page matrix

| Area | Current implementation | Backend state | Current audit state | Required evidence before complete |
|---|---|---|---|---|
| Sign in | shared `LifeMateSessionGate` | Supabase Auth | `ROUTE_PRESENT`, `VISUAL_PENDING`, `DEVICE_PENDING` | Persian/English, invalid credentials, keyboard |
| Sign up | shared `LifeMateSessionGate` | Supabase Auth | `ROUTE_PRESENT`, `VISUAL_PENDING`, `DEVICE_PENDING` | caregiver account bootstrap |
| Forgot password | shared `LifeMateSessionGate` | Supabase Auth | `ROUTE_PRESENT`, `VISUAL_PENDING`, `DEVICE_PENDING` | recovery flow |
| Dashboard/header | `dashboard_screen.dart`, `custom_app_header.dart` | current user/relationships/doses | `LIVE_READ`, `VISUAL_PENDING`, `DEVICE_PENDING` | exact bb287 hierarchy and floating nav |
| Patient selector | `_CareRecipientSelector` | active care relationships | `LIVE_READ`, `VISUAL_PENDING` | zero/one/multiple patients and long names |
| Accept invitation | dialog in `dashboard_screen.dart` | invitation acceptance | `LIVE_WRITE`, `E2E_PENDING`, `DEVICE_PENDING` | consent checkbox, wrong account, expiry, duplicate retry |
| Treatment queue | `_TreatmentQueueCard` | recipient dose occurrences | `LIVE_READ`, `VISUAL_PENDING` | current/next dose, empty/error/loading |
| Today summary | `_ProgressSummaryCard` | dose states | `LIVE_READ`, `VISUAL_PENDING` | zero totals and mixed statuses |
| Medication list | `_DoseListTile` | recipient dose occurrences | `LIVE_READ`, `VISUAL_PENDING` | missed/skipped/taken/scheduled variants |
| Alerts | header bottom sheet | dose states | `LIVE_READ`, `VISUAL_PENDING`, `DEVICE_PENDING` | no alerts and multiple alerts |
| Calendar | `calendar/calendar_screen.dart` | recipient dose occurrences | `LIVE_READ`, `VISUAL_PENDING`, `DEVICE_PENDING` | profile switch, empty/error, Jalali |
| Profile | `profile_screen.dart` | current caregiver | `LIVE_READ`, `VISUAL_PENDING`, `DEVICE_PENDING` | reference menu hierarchy and version label |
| Personal information | `profile_destination_screens.dart` | current user | `LIVE_READ`, `COMING_SOON`, `VISUAL_PENDING` | disabled edits and retry |
| Notifications | `profile_destination_screens.dart` | live alert view where available | `LIVE_READ`, `COMING_SOON`, `VISUAL_PENDING` | clear distinction between API alerts and future push |
| Referral | destination screen | unavailable | `COMING_SOON`, `VISUAL_PENDING` | no fake referral data |
| Support | destination screen | unavailable | `COMING_SOON`, `VISUAL_PENDING` | no fake ticket submission |
| Subscription | feature/profile destinations | unavailable | `COMING_SOON`, `VISUAL_PENDING` | original subscription journey retained |
| Family care | feature preview destination | unavailable beyond medication relationship | `COMING_SOON`, `VISUAL_PENDING` | no pregnancy/baby/family mock health data |
| Treatment management | feature preview destination | recipient data is read-only | `LIVE_READ`, `COMING_SOON`, `VISUAL_PENDING` | caregiver must not mutate patient treatment without a future scope |
| Profile switching | feature/profile destination and relationship selector | active relationships | `LIVE_READ`, `VISUAL_PENDING`, `DEVICE_PENDING` | state isolation when switching patients |
| Relationship revoke | dashboard and relationship screens | revoke API | `LIVE_WRITE`, `E2E_PENDING` | immediate post-revoke denial |
| Logout | `LifeMateAuth.signOut` | Supabase Auth | `LIVE_WRITE`, `DEVICE_PENDING` | session cleared and authenticated routes inaccessible |

## Button/interaction audit priorities

### P0

- Every bottom-navigation item opens the intended destination without gray/blank screens.
- Every profile menu item opens a real full page; unavailable mutations remain disabled.
- WellMate taken/skipped updates Home, Calendar and CareMate after refresh.
- CareMate never receives patient data without an active relationship and consent.
- Revocation removes CareMate access immediately.

### P1

- Header notification and profile actions.
- Retry buttons for current user, treatments, doses, calendar and relationships.
- Tab next/back/review/submit behavior in treatment creation.
- Small-screen keyboard and scroll behavior.
- Persian RTL, English LTR and large text scale.

## Confirmed gaps from the current source audit

1. The previous ledger overstates completion because most rows do not contain screenshot or physical-device evidence.
2. PR #30 is already merged into `main`; the parity work therefore continues on a new dedicated branch and Draft PR.
3. The profile pages contain stale hard-coded `0.8.0-beta.3` labels while both pubspec files are `0.8.0-beta.4+11`.
4. The current treatment form supports only one local time per plan and hard-codes `Asia/Tehran`; the requested flow requires one or multiple times and an explicit timezone value.
5. Caregiver invitation is bound to the entered email and produces a one-time token, but the client currently asks the patient to copy/share the token manually. Automatic delivery to the caregiver is not implemented and must not be claimed.
6. The authenticated two-account invitation → acceptance → read → revoke journey is still missing current live/device evidence.
7. Notification permission, reboot, timezone change, app update and OEM background behavior remain physical-device gates.
8. Visual parity for all routes remains open until captured evidence is attached to the exact commit.

## Immediate implementation sequence

1. remove stale version labels and add regression coverage;
2. make treatment schedule timezone explicit and support multiple daily times without changing the safe API boundary;
3. add route/button widget tests for both bottom navigation bars and profile menus;
4. add deterministic UI state fixtures for loading/empty/error/retry without presenting them as runtime health data;
5. execute authenticated API contract tests and the two-account journey;
6. run physical-device matrix and attach screenshots/results before declaring release-candidate readiness.
