# LifeMate Repository Instructions

## Repository structure
- `wellmate/`: Flutter patient/self-health app.
- `caremate/`: Flutter caregiver/family app.
- `packages/lifemate_client/`: shared authenticated mobile API client.
- `packages/lifemate_core/`: shared offline-first local health projection, durable execution and future sync/scheduler primitives.
- `supabase/functions/lifemate-api/`: the single healthcare API runtime for the current closed beta.
- `supabase/functions/lifemate-admin-api/`: separate internal Command Center API boundary; it is not a healthcare API shortcut.
- `supabase/migrations/`: **canonical forward PostgreSQL business-schema migrations**.
- `supabase/infrastructure/`: Supabase-specific Auth/Storage operational SQL that is not part of the portable business schema.
- `backend-dotnet/`: ASP.NET Core domain/reference implementation and tests. The four pre-ecosystem EF migrations are frozen historical bootstrap artifacts, not the forward schema owner.
- `backend/`: temporary Dart/Shelf demo backend. Do not extend or deploy it.

## Safe verification commands
- Backend restore: `dotnet restore backend-dotnet/LifeMate.sln`
- Backend build: `dotnet build backend-dotnet/LifeMate.sln --no-restore`
- Backend tests: `dotnet test backend-dotnet/LifeMate.sln --no-build`
- Healthcare Edge format/check/tests: run the tasks in `supabase/functions/lifemate-api/deno.json`.
- Admin Edge format/check/tests: run the tasks in `supabase/functions/lifemate-admin-api/deno.json`.
- Canonical DB validation: `.github/workflows/schema.yml` applies every `supabase/migrations/*.sql` file to fresh PostgreSQL 17 and reruns the chain for idempotency.
- Flutter verification: use the exact commands and SDK version in `.github/workflows/flutter.yml`.
- Shared offline core verification: use `.github/workflows/lifemate-core.yml`.

## Architecture rules
- `Account` is an authentication principal; `Person` is a human/data subject. Never collapse them in new domain design.
- Flutter uses Supabase Auth and calls only the reviewed LifeMate API for healthcare data. Flutter must never receive a DB connection string, service-role key or direct healthcare-table privilege.
- Health-domain ownership is by Person. Legacy `*_user_id` compatibility columns may remain during a phased migration, but new cross-domain contracts use `person_id`.
- Relationship, scoped data authorization, consent, commercial entitlement and administrative staff authorization are separate concepts. Premium state or an admin role never grants another person's health data.
- New production schema changes go only to `supabase/migrations`. Do not add new EF Core production migrations.
- Business-schema SQL should remain portable PostgreSQL. Supabase-specific Auth/Storage administration belongs behind infrastructure adapters or `supabase/infrastructure`.
- Do not add healthcare business logic to a second API runtime. Moving runtime responsibility to ASP.NET Core requires contract parity, staged cutover and retirement of the Edge implementation.
- The healthcare Edge runtime requires a dedicated invitation/contact hashing secret of at least 32 characters. Never reuse the Supabase service-role credential.
- Secondary commercial/pharma analytics is disabled by default. Health Connect / Android-health-permission sourced data is hard-blocked from commercial export.
- Offline-first owner health execution follows `Server = canonical shared truth; Device = durable local execution projection`. Product modules must reuse the shared local store/scheduler/outbox architecture instead of creating one database/queue per app.
- Protected local health state is environment + Account + Person isolated. Pending health mutations must never be silently dropped by migration, account switch, retry or storage-key failure.

## Command Center rules
- The browser-side `lifemate-admin` application must never query or mutate sensitive production healthcare tables directly.
- Admin authentication uses Supabase Auth, but every authenticated Command Center API operation must also validate active admin membership and the required server-side capability.
- Command Center authenticated API access requires MFA/AAL2.
- `lifemate_admin_runtime` is a separate least-privilege DB identity and must not receive ordinary access to the `lifemate` health schema or `care` health read models.
- `health.read.elevated` and `women_health.read.elevated` are not ordinary role permissions. Sensitive access is subject-specific, reasoned, time-bound, approved and audited.
- `admin.audit_events` is append-oriented for the normal Admin API runtime: never grant it UPDATE, DELETE or TRUNCATE.
- Do not add arbitrary SQL, unrestricted database tooling or unrestricted AI database access to the Admin API.
- Admin mutations require authorization, validation, idempotency/retry behavior and audit evidence.

## Change rules
- Never commit secrets, production connection strings, service-role keys, JWTs, refresh tokens, OTP codes, signing keystores, passwords, PII or health records.
- Never edit the four reviewed historical EF Core migration files to change deployed state.
- Use focused branches/commits and a reviewable pull request.
- Authentication, person ownership, consent, caregiver access, entitlement, admin capability authorization, idempotency and revocation are enforced server-side and tested with unrelated-user/role scenarios.
- Do not run database migrations automatically at API startup or Edge deployment.
- Do not remove legacy compatibility columns/tables until repository search, API/client migration, telemetry and rollback gates prove them unused.
- Internal APK artifacts are not a stable beta release until the release gate in issue #14 passes.
