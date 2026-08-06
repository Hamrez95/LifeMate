# LifeMate Repository Instructions

## Repository structure
- `wellmate/`: Flutter patient/self-health app.
- `caremate/`: Flutter caregiver/family app.
- `packages/lifemate_client/`: shared authenticated mobile API client.
- `supabase/functions/lifemate-api/`: the single healthcare API runtime for the current closed beta.
- `supabase/migrations/`: **canonical forward PostgreSQL business-schema migrations**.
- `supabase/infrastructure/`: Supabase-specific Auth/Storage operational SQL that is not part of the portable business schema.
- `backend-dotnet/`: ASP.NET Core domain/reference implementation and tests. The four pre-ecosystem EF migrations are frozen historical bootstrap artifacts, not the forward schema owner.
- `backend/`: temporary Dart/Shelf demo backend. Do not extend or deploy it.

## Safe verification commands
- Backend restore: `dotnet restore backend-dotnet/LifeMate.sln`
- Backend build: `dotnet build backend-dotnet/LifeMate.sln --no-restore`
- Backend tests: `dotnet test backend-dotnet/LifeMate.sln --no-build`
- Edge format/check/tests: run the tasks in `supabase/functions/lifemate-api/deno.json`.
- Canonical DB validation: `.github/workflows/schema.yml` applies every `supabase/migrations/*.sql` file to fresh PostgreSQL 17 and reruns the chain for idempotency.
- Flutter verification: use the exact commands and SDK version in `.github/workflows/flutter.yml`.

## Architecture rules
- `Account` is an authentication principal; `Person` is a human/data subject. Never collapse them in new domain design.
- Flutter uses Supabase Auth and calls only the reviewed LifeMate API for healthcare data. Flutter must never receive a DB connection string, service-role key or direct healthcare-table privilege.
- Health-domain ownership is by Person. Legacy `*_user_id` compatibility columns may remain during a phased migration, but new cross-domain contracts use `person_id`.
- Relationship, scoped data authorization, consent and commercial entitlement are separate concepts. Premium state never grants another person's health data.
- New production schema changes go only to `supabase/migrations`. Do not add new EF Core production migrations.
- Business-schema SQL should remain portable PostgreSQL. Supabase-specific Auth/Storage administration belongs behind infrastructure adapters or `supabase/infrastructure`.
- Do not add healthcare business logic to a second API runtime. Moving runtime responsibility to ASP.NET Core requires contract parity, staged cutover and retirement of the Edge implementation.
- The Edge runtime requires a dedicated invitation/contact hashing secret of at least 32 characters. Never reuse the Supabase service-role credential.
- Secondary commercial/pharma analytics is disabled by default. Health Connect / Android-health-permission sourced data is hard-blocked from commercial export.

## Change rules
- Never commit secrets, production connection strings, service-role keys, JWTs, refresh tokens, OTP codes, signing keystores, passwords, PII or health records.
- Never edit the four reviewed historical EF Core migration files to change deployed state.
- Use focused branches/commits and a reviewable pull request.
- Authentication, person ownership, consent, caregiver access, entitlement, idempotency and revocation are enforced server-side and tested with unrelated-user scenarios.
- Do not run database migrations automatically at API startup or Edge deployment.
- Do not remove legacy compatibility columns/tables until repository search, API/client migration, telemetry and rollback gates prove them unused.
- Internal APK artifacts are not a stable beta release until the release gate in issue #14 passes.
