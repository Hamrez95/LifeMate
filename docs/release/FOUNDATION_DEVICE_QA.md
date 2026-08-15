# LifeMate Foundation physical-device QA contract

Status: **human evidence required**. This checklist defines the current exact-main physical verification required before a LifeMate Android artifact may be called a stable invite-only beta. It does not mark any device check passed by itself.

Applies to both:

- WellMate — `com.lifemate.wellmate`
- CareMate — `com.lifemate.caremate`

Canonical release gate: GitHub issue #170 and the manual `main-final-android-release` workflow.

## Candidate identity

Every physical QA record must state the exact artifact being tested. Do not test one commit and approve another.

Record:

- exact `main` commit SHA;
- workflow run ID;
- LifeMate release/build version;
- WellMate APK SHA-256;
- CareMate APK SHA-256;
- WellMate signing certificate SHA-256;
- CareMate signing certificate SHA-256;
- APK-derived `minSdkVersion` and `targetSdkVersion` for both apps;
- API release SHA reported by `/health`;
- tester/device/date.

If any artifact is rebuilt or the deployed Edge SHA changes, the affected evidence must be repeated.

## Representative device matrix

At minimum use installed release-signed APKs on representative physical Android devices. Record for each device:

| Field | Evidence |
|---|---|
| Manufacturer / model | pending |
| Android version / API level | pending |
| Screen size / resolution | pending |
| Locale | `fa` and `en` coverage required |
| Text scale | normal + enlarged coverage required |
| Battery/OEM restriction state | record actual setting |
| WellMate install / version | pending |
| CareMate install / version | pending |

The final supported Android range is recorded from the actual release APK metadata plus the physical devices exercised. Do not infer support from a developer machine alone.

## P0 install, identity and authentication

For both apps:

- [ ] clean install succeeds using the release-signed APK;
- [ ] package ID and app label are correct;
- [ ] app launches without debug/runtime configuration leakage;
- [ ] Email + Password sign-in succeeds for dedicated beta identities;
- [ ] invalid credentials return generic user-safe errors;
- [ ] sign-out clears the active session and protected screens are no longer accessible;
- [ ] session is restored correctly after process kill/relaunch;
- [ ] expired/refreshed session behavior is recoverable and does not expose raw Supabase errors;
- [ ] offline startup/loading/error states are understandable and recoverable;
- [ ] Google Auth remains hidden when `ENABLE_GOOGLE_AUTH=false`;
- [ ] Phone OTP remains unavailable when `ENABLE_PHONE_OTP=false`.

## P0 core healthcare journey

Use dedicated patient, caregiver and unrelated beta accounts. Do not use real medical information for QA fixtures.

- [ ] patient signs in to WellMate;
- [ ] patient creates or opens a synthetic medication/treatment schedule;
- [ ] generated dose occurrence appears at the correct local date/time;
- [ ] patient records Taken / «مصرف کردم» once;
- [ ] repeated/retried action does not create a duplicate side effect;
- [ ] caregiver sees only consent-scoped status in CareMate;
- [ ] unrelated account cannot see patient data;
- [ ] patient revokes caregiver access;
- [ ] CareMate loses revoked access after refresh/relaunch;
- [ ] stale/offline UI does not continue presenting revoked sensitive content as authoritative;
- [ ] no raw UUID/token/health payload appears in visible error UI.

## P0 notification and reminder lifecycle

These checks must be performed on physical Android because emulator/unit coverage is not accepted as evidence for OS/OEM scheduling behavior.

- [ ] first-run notification permission UX is understandable;
- [ ] permission denial does not crash or trap the user;
- [ ] permission can be restored from Android settings and the app recovers;
- [ ] exact-alarm unavailable/fallback behavior remains functional and transparent;
- [ ] a synthetic reminder fires at the expected local time;
- [ ] lock-screen notification minimizes sensitive treatment information according to current privacy rules;
- [ ] reminder schedule is restored after device reboot;
- [ ] reminder schedule is recalculated after timezone change;
- [ ] reminder schedule remains valid after app update;
- [ ] process kill/relaunch does not silently lose the next reminder;
- [ ] temporary API outage does not remove already scheduled local reminders;
- [ ] reconnect flushes durable eligible actions without duplicate intake events;
- [ ] OEM battery restriction behavior/limitation is recorded rather than silently marked pass.

## P0 privacy, export, deletion and crash telemetry

- [ ] profile export action clearly describes a portable JSON copy rather than a full raw database dump;
- [ ] export warning makes clipboard sensitivity clear before copying;
- [ ] deletion confirmation accurately describes immediate disable/revoke plus asynchronous deletion/anonymization;
- [ ] deleting account signs the user out after accepted request;
- [ ] another person's shared healthcare record is not deleted merely because the deleting user acted as caregiver;
- [ ] crash/error UX does not expose raw health payload, JWT, email, SQL or stack trace;
- [ ] one controlled synthetic crash/error reaches privacy-safe telemetry when authenticated telemetry credentials are enabled;
- [ ] telemetry submission failure does not cause a crash loop;
- [ ] screenshots/recents/lock-screen behavior are reviewed for accidental sensitive disclosure where applicable.

## P0 RTL/LTR and accessibility

Review both WellMate and CareMate, not only the login screen.

### Persian / RTL

- [ ] primary flows render RTL correctly;
- [ ] Persian copy is not clipped or visually reversed;
- [ ] Persian digits/date/time presentation is coherent where the product expects it;
- [ ] Jalali/Gregorian presentation does not cause wrong-day treatment/reminder behavior;
- [ ] back/navigation affordances follow the current RTL design without trapping the user.

### English / LTR

- [ ] primary flows render LTR correctly;
- [ ] switching locale does not leave mixed stale layout direction;
- [ ] dates/times remain semantically the same after locale change.

### Accessibility / older-adult usability

- [ ] enlarged system text does not clip critical labels/actions;
- [ ] small-screen layout has no keyboard/button overflow on auth, medication and profile flows;
- [ ] critical actions have adequate touch target size;
- [ ] focus/semantics labels are meaningful for interactive controls;
- [ ] status is not communicated by color alone;
- [ ] contrast remains legible for text, disabled states and destructive actions;
- [ ] loading/error/offline states are announced/understandable and do not create dead ends;
- [ ] Reduce Motion / animation behavior does not block core actions where applicable.

## P0 lifecycle / update / rollback

- [ ] upgrade from the previous installed internal build preserves expected account/session/data state or fails safely according to the documented update path;
- [ ] release-signed APK cannot silently fall back to debug signing;
- [ ] Android reports the expected signing certificate;
- [ ] reinstall behavior is understood and does not imply local data is a server backup;
- [ ] rollback procedure is reviewed against the exact deployed API/schema compatibility window;
- [ ] after app update, notifications and session recovery are rechecked.

## Evidence record template

Create one record per candidate and keep failures visible.

```text
Candidate main SHA:
Workflow run:
API /health SHA:
WellMate APK SHA-256:
WellMate cert SHA-256:
WellMate minSdk / targetSdk:
CareMate APK SHA-256:
CareMate cert SHA-256:
CareMate minSdk / targetSdk:

Device 1:
- model:
- Android/API:
- locale/text scale:
- battery restriction state:
- checks passed:
- checks failed:
- notes:

Device 2:
- model:
- Android/API:
- locale/text scale:
- battery restriction state:
- checks passed:
- checks failed:
- notes:

Open P0 findings:
Tester:
Tested at UTC:
```

Do not place account passwords, JWTs, phone/email values, medication names or real health values in the evidence record.

## Exit rule

A stable invite-only beta is not approved until:

1. exact-main Edge/version and live role smoke gates pass;
2. release-signed WellMate/CareMate artifacts and hashes/certificates are recorded;
3. every applicable P0 physical check above has evidence on representative devices;
4. unresolved failures are either fixed and retested or explicitly removed from release scope by a safety-preserving product decision;
5. jurisdiction-specific privacy/legal review and other external Foundation blockers are resolved separately.

CI success, emulator tests, local PostgreSQL smoke, or this checklist alone can never be used as a substitute for the physical-device evidence.
