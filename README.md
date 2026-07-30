# LifeMate

LifeMate is a connected digital-health and family-care ecosystem for helping a patient follow a treatment plan while an explicitly authorized caregiver can provide timely support.

## Products

- **WellMate** — patient-facing Flutter application for medication schedules, reminders and adherence reporting.
- **CareMate** — caregiver/family Flutter application for consent-scoped monitoring and support.
- **LifeMate.Api** — ASP.NET Core backend that owns healthcare business rules, authorization, audit and PostgreSQL persistence.

## Architecture baseline

```text
WellMate / CareMate
        |
        | Supabase Auth JWT + HTTPS API requests
        v
   LifeMate.Api
        |
        v
 PostgreSQL
```

Supabase may provide managed Auth and PostgreSQL for the beta, but mobile clients must not directly read or mutate healthcare tables. The repository must have exactly one production healthcare API/authorization boundary; the active architecture decision is tracked in [issue #18](../../issues/18).

## Repository map

```text
wellmate/          Flutter patient application
caremate/          Flutter caregiver application
backend-dotnet/    Production ASP.NET Core modular monolith and tests
backend/           Temporary legacy Dart/Shelf demo backend; not production
assets/            Shared product artwork and design assets
docs/              Product, development, security and operations documentation
.github/workflows/ Path-scoped backend and Flutter CI
```

Shared Flutter client code and deployment adapters may be introduced through reviewed pull requests; they are not allowed to create a second, untested source of healthcare business rules.

## Delivery control

- [Launch roadmap](../../issues/7)
- [Stable beta release gate](../../issues/14)
- [Database/RLS hardening](../../issues/16)
- [API-boundary decision](../../issues/18)

`main` is reserved for reviewed, releasable increments. Production code changes use one focused branch and pull request with green CI. Internal APK artifacts are test builds until every stable-release gate is complete.

## Verification

### Backend

```bash
dotnet restore backend-dotnet/LifeMate.sln
dotnet build backend-dotnet/LifeMate.sln --configuration Release --no-restore
dotnet test backend-dotnet/LifeMate.sln --configuration Release --no-build
```

### Flutter

Run dependency resolution, analysis and tests from each application directory. The authoritative versions and complete CI commands live in `.github/workflows/flutter.yml`.

## Safety rules

- Never commit secrets, tokens, production connection strings, signing keystores or health data.
- Keep authentication, ownership, consent and caregiver authorization checks server-side.
- Do not make clinical diagnosis, prescribing, emergency-response or drug-interaction claims in the beta.
- Apply database migrations only after review, green CI and a documented rollback/restore plan.
- Validate a release on representative real Android devices before distribution.

See [AGENTS.md](AGENTS.md) and [docs/development/WORKFLOW.md](docs/development/WORKFLOW.md) for repository instructions.