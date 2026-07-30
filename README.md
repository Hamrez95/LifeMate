# LifeMate

LifeMate is a connected digital-health and family-care ecosystem that helps a patient follow a treatment plan while an explicitly authorized caregiver can provide timely support.

## Products

- **WellMate** — patient-facing Flutter application for medication schedules, reminders and adherence reporting.
- **CareMate** — caregiver/family Flutter application for consent-scoped monitoring and support.
- **LifeMate closed-beta API** — hardened Supabase Edge Function for authenticated healthcare workflows.
- **ASP.NET Core reference backend** — canonical domain model, EF migrations and parity/reference tests for the same PostgreSQL schema.

## Closed-beta architecture

```text
WellMate / CareMate
        |
        | Supabase Auth session + HTTPS
        v
Supabase Edge Function: lifemate-api
        |
        | least-privilege server connection
        v
PostgreSQL schema: lifemate
```

Supabase provides Auth, the Edge runtime and managed PostgreSQL for the zero-cost closed beta. Mobile clients never directly read or mutate healthcare tables and never receive database/service-role credentials.

The repository has exactly one healthcare API runtime for this release: `supabase/functions/lifemate-api`. `backend-dotnet` remains the canonical schema/domain reference and owns reviewed EF migrations, but is not called by the closed-beta apps. Moving the runtime to ASP.NET Core later is an explicit migration—not a second parallel API.

## Repository map

```text
wellmate/                         Flutter patient application
caremate/                         Flutter caregiver application
packages/lifemate_client/         Shared authenticated mobile client
supabase/functions/lifemate-api/  Closed-beta healthcare API runtime
backend-dotnet/                   Domain/schema reference, EF migrations and tests
backend/                          Temporary legacy Dart/Shelf demo; not production
assets/                           Product artwork and design assets
docs/                             Product, development, security and operations docs
.github/workflows/                Path-scoped backend, Edge and Flutter CI
```

## Delivery control

- [Launch roadmap](../../issues/7)
- [Stable beta release gate](../../issues/14)
- [Database/RLS hardening](../../issues/16)
- [Closed-beta API decision](../../issues/18)

`main` is reserved for reviewed, releasable increments. Production code changes use one focused branch and pull request with green CI. Internal APK artifacts remain test builds until the stable-release gate is complete.

## Verification

### Edge API

```bash
cd supabase/functions/lifemate-api
deno fmt --check
deno task check
deno task test
```

The authoritative workflow additionally applies canonical EF migrations to temporary PostgreSQL and tests patient, caregiver and unrelated-user journeys.

### Canonical schema/reference backend

```bash
dotnet restore backend-dotnet/LifeMate.sln
dotnet build backend-dotnet/LifeMate.sln --configuration Release --no-restore
dotnet test backend-dotnet/LifeMate.sln --configuration Release --no-build
```

### Flutter

Run dependency resolution, analysis and tests from each application directory. The authoritative versions and complete commands live in `.github/workflows/flutter.yml`.

## Safety rules

- Never commit secrets, tokens, production connection strings, signing keystores or health data.
- Keep authentication, ownership, consent, caregiver authorization, idempotency and revocation checks server-side.
- Never reuse the Supabase service-role key as an invitation/contact hashing secret.
- Do not make clinical diagnosis, prescribing, emergency-response or drug-interaction claims in the beta.
- Apply database migrations only after review, green CI and a documented backup/rollback plan.
- Validate a release on representative real Android devices before distribution.

See [AGENTS.md](AGENTS.md), [the development workflow](docs/development/WORKFLOW.md) and [the beta operations runbook](docs/operations/BETA_OPERATIONS_RUNBOOK.md).
