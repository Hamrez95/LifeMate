# LifeMate Repository Instructions

## Repository structure
- `wellmate/`: Flutter patient app.
- `caremate/`: Flutter caregiver app.
- `packages/lifemate_client/`: shared authenticated mobile API client.
- `supabase/functions/lifemate-api/`: the single healthcare API runtime for the zero-cost closed beta.
- `backend-dotnet/`: canonical domain/schema implementation, EF migrations and reference tests; not the closed-beta mobile runtime.
- `backend/`: temporary Dart/Shelf demo backend. Do not extend or deploy it.

## Safe verification commands
- Backend restore: `dotnet restore backend-dotnet/LifeMate.sln`
- Backend build: `dotnet build backend-dotnet/LifeMate.sln --no-restore`
- Backend tests: `dotnet test backend-dotnet/LifeMate.sln --no-build`
- Local database: `docker compose -f backend-dotnet/docker-compose.yml up -d postgres`
- Edge format/check/tests: run the tasks in `supabase/functions/lifemate-api/deno.json`.
- Flutter verification: use the exact commands and SDK version in `.github/workflows/flutter.yml`.

## Closed-beta architecture rules
- Flutter uses Supabase Auth and calls only the reviewed `lifemate-api` Edge Function for healthcare data.
- Flutter must never receive a database connection string, service-role key or direct healthcare-table privilege.
- EF Core migrations in `backend-dotnet` remain the source of truth for the `lifemate` PostgreSQL schema.
- Do not add healthcare business logic to a second API runtime. A future move back to ASP.NET Core requires a reviewed migration plan, parity tests and retirement of the Edge runtime.
- The Edge runtime requires a dedicated contact/invitation hashing secret of at least 32 characters. Never reuse the Supabase service-role key or a signing credential.

## Change rules
- Never commit secrets, production connection strings, service-role keys, JWTs, refresh tokens, OTP codes, signing keystores or passwords.
- Never modify a reviewed generated EF Core migration manually; create a follow-up migration.
- Use one focused branch and pull request per change.
- Authentication, ownership, consent, caregiver access, idempotency and revocation must be enforced server-side and tested with an unrelated-user scenario.
- Do not run database migrations automatically at API startup or Edge deployment.
- Internal APK artifacts are not a stable beta release until the release gate in issue #14 passes.
