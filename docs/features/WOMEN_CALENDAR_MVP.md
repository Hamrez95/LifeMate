# Women Calendar pilot and caregiver notification boundary

Status: Internal pilot only. No Production migration or rollout is authorized by this document.

## Product name

The capability is presented in WellMate subscription surfaces as **تقویم بانوان**. Internal domain/API names use `women-calendar` to avoid ambiguous UI wording.

## Activation

- The feature is compile-time gated by `ENABLE_WOMEN_CALENDAR_PILOT` and defaults to `false`.
- In an explicitly enabled internal build, tapping **تقویم بانوان** activates the profile without charging or contacting a payment provider.
- The same surface exposes an explicit deactivation action.
- Deactivation hides the navigation destination and prevents caregiver reads while retaining the owner history for later reactivation.

## Owner data

WellMate owns:

- last period start date;
- usual cycle length;
- usual bleeding length;
- actual period episodes;
- reminder preference;
- optional private notes.

Predictions are estimates, versioned and deterministic. The MVP does not claim an exact ovulation day, fertility window, contraception result, diagnosis or treatment.

## Caregiver access

- Existing medication access remains part of the active care relationship.
- `canViewWomenCalendar` is a separate permission, disabled by default.
- Only the WellMate owner may change this permission.
- CareMate receives a summary only when the relationship is active, the owner profile is enabled and the permission is true.
- Private notes are never returned to CareMate.
- Revocation or deactivation must fail closed immediately.

## Support actions

CareMate may record only non-diagnostic supportive actions from a fixed allowlist: hydration, rest, warmth and chores. These actions do not represent medical advice or medication administration.

## Notifications

- WellMate schedules each upcoming medication occurrence locally.
- CareMate schedules at most the earliest upcoming medication occurrence per active care recipient, so one patient cannot flood the notification tray.
- Notification payloads contain a patient display name, medicine name, dose text and scheduled time; they do not include cycle notes or other sensitive women-calendar details.

## Release gates

Before any Production activation:

1. migration and API tests pass in CI;
2. owner/caregiver/unrelated/revoked/permission-off/profile-off scenarios pass against Candidate;
3. Android notification permission, reboot, timezone and OEM battery behavior are physically verified;
4. Persian digits, Jalali dates, RTL navigation, small-screen and large-text tests pass;
5. privacy/security review signs off on the migration, audit events and response payloads.
