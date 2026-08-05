# Women Companion Experience

This feature provides a mobile-first women-cycle experience in WellMate and a consent-scoped spouse companion experience in CareMate.

## Product boundaries

- The feature covers menstrual-cycle tracking, phase estimates, daily mood, energy, pain, symptoms, reminders, reports, and supportive spouse actions.
- Pregnancy, trying to conceive, child care, pregnancy probability, and contraception guidance are outside this release.
- Cycle phases, fertile windows, and ovulation dates are calendar estimates only. They are not diagnostic and must not be used to confirm ovulation or prevent pregnancy.

## Privacy contract

- The WellMate owner controls women-calendar access at the relationship level.
- Daily wellbeing summaries are private by default.
- Sharing is explicit and per daily entry.
- CareMate may receive mood, energy level, pain level, and selected symptom codes only when that entry is shared.
- Private notes must never be returned by a caregiver endpoint, written to audit metadata, or shown in CareMate.
- Revoked or inactive access fails closed.

## UI contract

- Both screens are native Flutter UI and do not use screenshots as runtime backgrounds.
- WellMate uses a soft lilac, pink, peach, and warm-white visual language for this feature only.
- CareMate uses the word `همدم` only inside the spouse companion experience; the rest of CareMate retains caregiver terminology.
- Layouts must remain usable on narrow Android screens, with Persian RTL, large text, and content ending above bottom navigation.

## Release gates

- Shared client, WellMate, and CareMate format/analyze/test.
- Active-feature widget tests with `ENABLE_WOMEN_CALENDAR_PILOT=true`.
- Edge Function format, type, unit, and PostgreSQL integration tests.
- Additive migration validation and privacy regressions.
- Android release builds for WellMate and CareMate.
- APK package and manifest inspection before delivery.
