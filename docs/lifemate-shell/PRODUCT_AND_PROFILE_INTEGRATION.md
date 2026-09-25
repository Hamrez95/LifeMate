# Shell Product and Profile Integration

Status: embedded entry paths implemented; authenticated device acceptance remains open.

## Authentication and product roots

`LifeMateExperienceGate` restores the one Supabase Auth session and creates the shell-owned `LifeMateApiClient`. `LifeMateShellAuth` owns the branded email/password and phone OTP entry surfaces. The shell release workflow enables phone OTP with `ENABLE_PHONE_OTP=true`.

The production module registry mounts WellMate, CareMate and CocoonMate from the shell. WellMate and CareMate embedded roots receive the shell API client and locale; their standalone auth/onboarding entry screens are skipped only in embedded mode. CocoonMate uses the existing authenticated `LifeMateAuth` session. Product headers hand profile navigation back to the shell. CareMate's recipient selector remains a product relationship feature, not a second global account profile. Product enrollment, relationship and entitlement gates remain product-domain rules.

The shell's `ProfileYouScreen` is the shared account/Person profile destination. Product settings and domain actions remain product-owned; this integration does not copy profile data into local product stores or add backend schema. A full field-by-field merge of legacy product profile forms still needs a product inventory and explicit field ownership review.

## Routes and known gaps

- Living Camp WellMate, CareMate and Reproductive Context hotspots resolve to the embedded WellMate, CareMate and CocoonMate routes.
- FitMate remains unavailable because this repository has no FitMate module.
- The shell Today panel still uses `UnavailableTodaySource`; it must stay empty/unavailable until a reviewed production `lifemate.today.v1` aggregate exists.
- No editable/exported `.riv` avatar is included. Current 2.5D scene/vector character work is a lightweight fallback, not a Rive deliverable.
- The shell locally builds for web. Android release packaging could not be validated in this Windows environment because Gradle/JDK failed to establish its loopback socket.

## Acceptance still required

On an authenticated device, verify one login opens each available product without a product sign-in page; opening each product's global profile returns to the shell profile; sign-out returns to shell auth; shell locale and shared profile edits remain visible; and account/Person changes invalidate mounted module state. Then verify SMS OTP against the configured provider and run the Android release gate on a supported Gradle/JDK host. Until that device acceptance completes, this PR only establishes and unit-tests the host boundary.
