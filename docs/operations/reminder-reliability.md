# WellMate reminder reliability contract

This document separates what the repository proves automatically from what still requires representative Android-device QA before stable beta.

## Source-level contract

WellMate treatment reminders are scheduled with `flutter_local_notifications` using timezone-aware `zonedSchedule` and `AndroidScheduleMode.exactAllowWhileIdle`.

The Android manifest keeps the platform/plugin recovery requirements for scheduled notifications:

- `POST_NOTIFICATIONS`;
- `SCHEDULE_EXACT_ALARM`;
- `RECEIVE_BOOT_COMPLETED`;
- `ScheduledNotificationReceiver`;
- `ScheduledNotificationBootReceiver` for `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED` and supported quick-boot broadcasts.

When the WellMate process returns to `AppLifecycleState.resumed`, `HomeScreen` performs a debounced full data refresh. The home content receives a new refresh token, re-fetches the current schedule from the LifeMate API, and calls `NotificationProvider.syncReminders(...)`. This is the application-level reconciliation path after device/app state changes, including a timezone change observed while the app was inactive.

`wellmate/test/reminder_reliability_contract_test.dart` prevents these pieces from being removed independently without CI failing.

## What this does not prove

Source configuration is not physical-device evidence. Stable beta still requires QA on the actual supported Android range for:

1. notification permission denied -> explanation/recovery -> permission granted;
2. exact-alarm permission denied/revoked and then restored;
3. scheduled reminder survives a normal device reboot;
4. scheduled reminder survives an app update (`MY_PACKAGE_REPLACED` path);
5. change device timezone while WellMate is backgrounded, resume the app, and verify the refreshed reminder fires at the expected treatment instant;
6. at least one OEM with aggressive background restrictions if that OEM is in the supported beta device set;
7. reminder content remains private on the lock screen and uses the expected Persian/English copy.

Do not mark the stable-beta device reminder gate complete from CI alone. Record device model, Android version, app commit/build, expected reminder time, actual result, permission state, and whether the app had to be opened after the state change.

## Failure handling

- A reminder-scheduling failure must not prevent the home schedule from loading.
- The backend treatment/adherence record remains the source of truth; local notifications are delivery aids, not authoritative medical state.
- Do not add an unbounded background retry loop to compensate for OEM notification restrictions.
- If a device cannot reliably deliver reminders under its power-management settings, document the limitation and provide user-facing remediation rather than silently claiming reliability.
