# LifeMate closed-beta operations runbook

## Deployment boundary

- Supabase provides Auth, the reviewed `lifemate-api` Edge runtime and PostgreSQL.
- WellMate and CareMate authenticate with Supabase and send healthcare requests only to `lifemate-api`.
- The Edge Function is the only closed-beta healthcare API runtime.
- `backend-dotnet` remains the canonical domain/schema implementation, EF migration source and parity/reference test suite; it is not deployed in parallel for this beta.
- Database migrations are never run automatically at function startup or deployment.

## Required Edge configuration

- `SUPABASE_DB_URL` — secret, server-side only;
- `SUPABASE_URL`;
- `SUPABASE_PUBLISHABLE_KEYS.default` or `SUPABASE_ANON_KEY`;
- `LIFEMATE_CONTACT_HASHING_SECRET` or `SUPABASE_SECRET_KEYS.contact_hashing`, at least 32 characters and dedicated to invitation/contact HMAC;
- `LIFEMATE_RELEASE_VERSION`, set to the released version/commit label.

Never use or expose `SUPABASE_SERVICE_ROLE_KEY` for contact hashing or mobile authentication. Never place database URLs, secrets, refresh tokens or signing credentials in Flutter build variables.

Rotating the contact hashing secret invalidates pending invitations. Before rotation, record the reason, expire pending invitations, deploy the new secret and instruct affected patients to create new invitations. Active relationships remain valid.

## Pre-deployment

1. Identify the exact commit and intended release version.
2. Confirm Edge format, strict type-check, unit/security tests and PostgreSQL role journey are green.
3. Confirm backend restore/build/tests, EF migration discovery and `has-pending-model-changes` are green.
4. Confirm Flutter shared client, WellMate and CareMate analysis/tests/build checks are green.
5. Inspect the Supabase backup/PITR capability available on the selected plan and verify a recoverable backup before any schema change.
6. Apply only reviewed EF migrations as a separate controlled action.
7. Set the dedicated hashing secret and release version in the Edge secret store.
8. Deploy the exact reviewed `lifemate-api` source.
9. Verify `/health` reports `status=ok`, `database=ready` and the expected release version.
10. Verify unauthenticated healthcare requests return 401.
11. Run the controlled two-account smoke journey: patient bootstrap, medication/plan, occurrence, Taken/Skipped, invitation, caregiver acceptance/read, revocation and post-revocation denial.
12. Run an unrelated third-account access attempt and verify denial without resource disclosure.
13. Record deployment time, commit, migration history, tester accounts, results and known limitations.

## Internal Android artifact

After the deployed API smoke test passes:
- build WellMate and CareMate from the exact reviewed commit;
- embed only public Supabase URL/publishable key and the reviewed Edge base URL;
- verify package IDs, version name/code, INTERNET permission and installability;
- label debug-signed output as `internal/unstable`;
- attach commit SHA, test checklist, known limitations and artifact expiry.

A debug-signed artifact is not a stable beta or store release.

## Rollback

- Function rollback means redeploying the prior reviewed Edge Function version and restoring its compatible secret configuration.
- Do not automatically run EF `Down()` in production.
- If schema compatibility is broken, stop writes, preserve evidence and use a reviewed forward-fix or backup restore.
- After rollback, repeat health, authentication, patient isolation, caregiver access and revocation smoke tests.
- Record the incident, timestamps, user impact and corrective action.

## Privacy-safe logging

Logs may contain correlation IDs, route templates, status codes, latency, release version and internal error classifications. Do not log access/refresh tokens, invitation tokens, passwords, full email/phone contacts, medication names, dose text or free-form health notes.

## Abuse and reliability notes

The Edge in-memory limiter is best-effort per-isolate defense only. It is not a distributed quota. If abuse appears during beta, pause invitations or affected writes and add a reviewed shared limiter rather than raising limits blindly.

## Beta incident priorities

- **P0:** cross-user disclosure, auth bypass, destructive data loss or leaked secret. Disable the affected path, revoke credentials, preserve evidence and notify the founder immediately.
- **P1:** reminders broadly failing, API unavailable, reports not persisting or revocation delayed. Pause new invitations and communicate the limitation.
- **P2:** isolated UX/device issue. Record reproducible details and address in the next beta patch.

## Export and account deletion

Founder-assisted export/deletion remains temporary. A tested authenticated self-service workflow is required before stable beta. Never delete a Supabase Auth user without first completing or safely scheduling deletion/export of corresponding application data and audit/retention handling.
