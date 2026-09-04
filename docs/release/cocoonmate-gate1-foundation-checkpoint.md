# CocoonMate Gate-1 foundation checkpoint

Issue: #787

Gate-1 separates automated foundation evidence from the required physical Android journey. Automated evidence may be merged independently, but #787 remains open until the same traceable candidate is exercised on a real Android device.

## Automated contract evidence

The Cocoon standalone host and reusable module must pass clean CI for:

- isolated Cocoon auth callback scheme;
- valid runtime bootstrap before product content is shown;
- Account/Person bootstrap fail-closed when Person is absent;
- application availability and enrollment independent from Commerce;
- authoritative Cocoon Commerce eligibility independent from entitlement state;
- unknown/unavailable/error Commerce or unknown entitlement fail closed;
- active entitlement alone cannot bypass Cocoon-specific Commerce eligibility;
- no active pregnancy routes to setup without creating an episode locally;
- expired/unauthorized session invokes sign-out and returns to authentication;
- API/network loss routes to explicit offline state;
- malformed or stale/untrusted runtime config never unlocks Cocoon;
- Persian RTL, English LTR and large-text module rendering;
- standalone Android APK build and non-colliding `com.mylifemate.cocoonmate` identity.

The release workflows from #785 additionally require environment guards, artifact provenance and exact SHA/build identity.

## Privacy / authority assertions

Gate-1 does not use relationship state, enrollment, a cached entitlement, or app navigation as pregnancy-health authorization. Launching Cocoon or tapping the pre-#788 setup action cannot create an episode. Safe host telemetry records event names only and does not include Person/Episode IDs, pregnancy dates, gestational age, symptom text or other reproductive PHI.

## Physical Android evidence — REQUIRED BEFORE CLOSING #787

Run the final journey against one exact candidate artifact generated from merged `main`. Record all of the following in #787 before closure:

- candidate commit SHA;
- GitHub workflow run and artifact name;
- artifact SHA-256/provenance file;
- Cocoon semantic version/build number;
- Android device model and OS/API level;
- backend project/environment and canonical migration baseline;
- install succeeds alongside WellMate/CareMate without package collision;
- Cocoon name/icon/launcher identity are correct;
- cold start and process-kill/restart succeed;
- Persian RTL startup/auth/bootstrap route;
- English LTR startup/auth/bootstrap route;
- signed-in Account resolves the intended Person;
- application unavailable/disabled is fail-closed;
- not-enrolled, not-entitled, entitled-without-pregnancy and active-pregnancy routes are authoritative;
- expired session returns to authentication;
- network/API loss does not expose stale shared pregnancy state;
- no pregnancy episode is created by install, launch, sign-in or enrollment alone;
- no reproductive PHI appears in generic diagnostics/notifications/screenshots used as evidence;
- no visible overflow/crash at normal and enlarged system text sizes.

Synthetic/test accounts and IDs must be used for checkpoint evidence. Do not paste real LMP, EDD, symptom history, measurements or other pregnancy PHI into GitHub/Notion.

## Gate outcome

`PASS` requires both automated CI and the physical-device evidence above. Until then the issue is `PENDING PHYSICAL DEVICE VERIFICATION`, and Phase-2 broad pregnancy UI work (#788/#614/#789/#790) must not be treated as Gate-1 accepted.
