# Offline-first local reminder scheduler

Issue: #830
Parent: #828
Depends on: #829, #474

## Invariant

`Server = canonical shared truth; Device = durable local execution engine`.

The server remains authoritative for shared health state and recurrence definitions. Once an owner has received a bounded future schedule, firing the corresponding medication, treatment, appointment, Women Health or Cocoon reminder must not require daily API, Supabase, FCM or other network availability.

## Shared execution boundary

`packages/lifemate_core` owns one reusable reminder execution engine for WellMate, Women Health, CocoonMate and the future unified shell.

Product modules provide projected reminder occurrences; they do not create another OS scheduler abstraction. The shared engine:

- accepts UTC trigger instants plus an explicit IANA timezone;
- keeps a bounded scheduling horizon and hard maximum reminder count;
- chooses the latest source revision for an occurrence;
- derives stable Android notification IDs from opaque source occurrence key + source revision;
- detects source/revision conflicts and notification-ID collisions fail-closed;
- removes superseded future notifications while leaving unrelated notification classes untouched;
- supports explicit preservation of user-created snoozes during reconciliation;
- attempts exact-while-idle delivery for owner treatment reminders and can fall back to inexact-while-idle when Android exact-alarm access is unavailable;
- never initializes a second notification-response owner.

The Flutter adapter is exposed through `package:lifemate_core/lifemate_reminders.dart`, which is intentionally web-safe and does not import the native SQLite store.

## Protected schedule metadata

`LifeMateLocalHealthReminderRegistry` reuses the encrypted #829 local health store and the existing `notificationSchedule` domain. It persists only execution metadata:

- schedule key;
- notification ID;
- source revision;
- trigger UTC;
- actual accuracy class.

Notification title, body and payload are deliberately not duplicated into the registry. Environment + Account + Person isolation is inherited from the shared local store. Product integration with the native registry is performed when that product adopts the #829 store projection (WellMate #832, Women Health #833, CocoonMate #834); no second database is introduced here.

## Existing scheduler migration

### WellMate owner reminders

`NotificationProvider` remains the single notification plugin initializer/response owner, but medication, treatment and appointment scheduling now projects `LifeMateLocalReminder` values and delegates OS scheduling to the shared core engine. Legacy WellMate payload prefixes remain recognized during reconciliation so app upgrades remove superseded pre-#830 pending notifications without duplication.

The reminder source key is based on existing opaque occurrence/deduplication identity and the server version is the source revision. Grouped medication reminders derive identity from the sorted opaque occurrence IDs + versions.

### Women Health

Cycle Insight no longer calls `zonedSchedule` directly. It uses the same core scheduler in inexact mode, keeps its privacy-minimized payload prefix, and reconciles older fixed-ID pending notifications during upgrade.

### CareMate

Caregiver/partner events are inherently remote/shared and remain outside this owner-local execution migration unless a future feature has a genuine owner-local execution requirement. #830 must not turn push-driven caregiver state into a second local source of truth.

### CocoonMate

CocoonMate consumes this scheduler for approved pregnancy appointments/check-ins/content reminders when its offline projection adapter lands. It must not add another scheduler implementation.

## Privacy

Scheduler IDs are deterministic hashes of opaque source identity + revision and never contain notification text. Shared core code does not log source keys, payloads or notification contents.

WellMate lock-screen title/body text is generic and does not include medication name, dosage, provider, specialty, appointment title or other health detail. Women Health reminder text contains no symptoms, pain, notes, fertility state or raw cycle dates.

## Android recovery

The existing Android host manifests keep `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`, `RECEIVE_BOOT_COMPLETED` and `MY_PACKAGE_REPLACED`, so the notification plugin can restore persisted future alarms after reboot/app replacement. WellMate also reconciles its current bounded server projection when the app resumes.

Exact-alarm permission is requested only after the existing contextual permission explanation. If exact access is denied or Android rejects an exact schedule call, the shared engine can schedule an inexact-while-idle fallback and exposes that degraded state to the provider instead of silently dropping the reminder.

## Verification boundary

Automated tests cover deterministic identity/revision behavior, bounded horizon, stale-revision cancellation, snooze preservation, exact-alarm denial/runtime fallback, registry cleanup and reuse of the protected local store. WellMate contract tests prevent owner and Women Health code from reintroducing direct parallel `zonedSchedule` paths.

The following acceptance evidence remains physical-device gated and must **not** be paper-closed by unit/CI tests:

- notification actually fires with network disabled;
- notification actually fires after app process kill;
- reboot restores and fires a future reminder;
- OEM battery/background restriction behavior;
- real Android timezone/manual-clock transitions;
- permission denial/recovery on supported Android versions.

The separately reported CocoonMate `temporarily unavailable` runtime/device bug remains deferred and is not part of #830 debugging.
