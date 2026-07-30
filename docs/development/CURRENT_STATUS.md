# Current development status

Last updated: 2026-07-30

## Completed and verified

- ASP.NET Core domain/schema foundation, canonical EF migrations and green reference CI.
- Supabase project restored with Auth and PostgreSQL available.
- v0.2 care relationships, v0.3 treatment management and v0.4 adherence schema/domain work.
- Connected Flutter client for Supabase Auth and healthcare API calls.
- WellMate medication, daily treatment, occurrence and Taken/Skipped flow.
- Caregiver invitation, explicit consent, acceptance, scoped adherence view and immediate revocation flow.
- Stable Android application IDs, launcher/header artwork and internal APK build path.
- Hardened `lifemate-api` Edge runtime with dedicated HMAC secret, strict validation, actor-scoped idempotency, retry-safe care flows and privacy-safe errors.
- Pinned Edge CI with 14 unit/security tests.
- PostgreSQL 17.5 journey covering patient, intended caregiver and unrelated/adversarial user; canonical EF migrations, cross-user denial, request-ID collision, retry, revocation, audit and reconnect all pass.

## Selected closed-beta architecture

```text
WellMate / CareMate
        ↓ Supabase Auth + HTTPS
Supabase Edge Function: lifemate-api
        ↓ server-only least-privilege connection
PostgreSQL schema: lifemate
```

The Edge Function is the only healthcare API runtime for the zero-cost closed beta. `backend-dotnet` remains the canonical domain/schema and EF migration reference; it is not deployed as a parallel API.

## Supabase project baseline

- Project: `lifemate` (`bwdvmniywyyijjauipnh`)
- Region: `eu-west-1`
- Previously observed status: healthy
- Repository migrations through `20260726222000_AddDoseAdherence`
- Legacy/demo table: `public.health_status`, not a source of truth

## Active release sequence

1. Merge the connected MVP integration after current Edge, Flutter and .NET CI are green.
2. Configure a dedicated 32+ character Edge contact/invitation hashing secret.
3. Deploy the exact reviewed Edge commit and verify health/version.
4. Complete live patient/caregiver/unrelated-account smoke tests.
5. Complete database runtime-role/RLS hardening in issue #16.
6. Build versioned internal Android artifacts from the exact deployed commit.
7. Run representative-device, Persian/RTL, reminder, offline, accessibility and crash testing.
8. Complete privacy/terms, self-service export/deletion, signing, backup/restore and monitoring gates before stable invite-only beta.

## External actions currently required for deployment

The connected Supabase tool must permit Edge Function secret management and deployment, or equivalent founder-owned Supabase credentials must be configured in a protected deployment workflow. Never paste an access token, database password, service-role key or signing keystore into an issue, chat, source file or public repository variable.

Human beta validation is distinct from automated role simulation. The repository now provides repeatable patient/caregiver/adversarial automation; real-device and real-human testing must still be recorded before calling the artifact stable.
