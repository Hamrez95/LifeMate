# Supabase closed-beta baseline

Project: `lifemate`  
Region: `eu-west-1`  
Project reference: `bwdvmniywyyijjauipnh`

## Selected beta boundary

For the zero-cost invite-only beta, Supabase provides:
- Auth for mobile identity;
- the reviewed `lifemate-api` Edge Function as the **single healthcare API runtime**;
- managed PostgreSQL for the `lifemate` application schema.

Flutter calls the Edge Function with the authenticated user's session. Flutter does not directly query or mutate healthcare tables and never receives a database or service-role credential.

`backend-dotnet` remains the canonical domain/schema reference. Reviewed EF Core migrations are the source of truth for PostgreSQL DDL and are exercised by both .NET integration tests and Edge/PostgreSQL role-journey tests. It is not a second closed-beta runtime.

## Verified repository state

- Supabase Auth is integrated into both Flutter apps.
- EF migrations through `20260726222000_AddDoseAdherence` are represented in the repository and deployed in the previously verified project state.
- The Edge API has pinned Deno CI, strict validation/security unit tests and PostgreSQL patient/caregiver/unrelated-user coverage.
- A legacy/demo table exists at `public.health_status`; it must not become a source of truth.

## Runtime configuration

Required by `lifemate-api`:
- `SUPABASE_DB_URL` — secret server-side database connection;
- `SUPABASE_URL`;
- `SUPABASE_PUBLISHABLE_KEYS.default` or `SUPABASE_ANON_KEY` for validating user sessions;
- `LIFEMATE_CONTACT_HASHING_SECRET` or `SUPABASE_SECRET_KEYS.contact_hashing` — dedicated high-entropy secret of at least 32 characters;
- optional `LIFEMATE_RELEASE_VERSION` for health/version evidence.

Forbidden:
- using `SUPABASE_SERVICE_ROLE_KEY` as an invitation/contact hashing secret;
- exposing any secret or database URL to Flutter;
- granting mobile `anon`/`authenticated` roles direct healthcare-table access;
- automatically applying migrations during function startup/deployment.

## Schema and deployment policy

1. EF Core migrations in `backend-dotnet` remain the source of truth for the `lifemate` schema.
2. A migration must pass .NET build/tests, model-snapshot validation and Edge PostgreSQL journey tests before application.
3. Verify a recoverable backup before applying a production migration.
4. Deploy the exact reviewed Edge commit separately from database migration.
5. Validate `/health`, unauthenticated rejection, authenticated bootstrap, patient isolation, invitation/acceptance, caregiver access, adherence reporting and post-revocation denial.
6. Record deployed commit, release version and migration history.

## Security hardening still required for stable beta

Tracked in issue #16:
- identify and document the exact PostgreSQL runtime role used by the Edge Function;
- apply/review defense-in-depth RLS or equivalent role restrictions without granting direct mobile access;
- confirm least-privilege grants against the deployed role;
- re-run direct-access denial, cross-user and post-revocation tests against the live project;
- review Supabase security/performance advisors after final DDL.

The Edge in-memory limiter is best-effort abuse resistance only; it is not a distributed/global rate-limit guarantee.

## Migration and rollback note

Changing `LIFEMATE_CONTACT_HASHING_SECRET` invalidates pending invitation hashes. Active caregiver relationships do not depend on that secret. Secret rotation therefore requires an explicit plan to expire pending invitations and communicate regeneration. Application rollback redeploys the prior reviewed Edge Function version; database rollback uses a reviewed forward-fix or backup restore, not an automatic EF `Down()`.

Retire `public.health_status` and the legacy Dart backend only after the connected Flutter path is released, observed and no longer needs that rollback route.
