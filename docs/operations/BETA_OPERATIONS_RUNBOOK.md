# LifeMate beta operations runbook

## Deployment boundary

- Supabase provides PostgreSQL and Auth.
- `LifeMate.Api` runs as the `backend-dotnet/Dockerfile` container on an HTTPS
  host.
- Flutter apps use Supabase only for authentication and send healthcare-data
  requests to `LifeMate.Api`.
- Database migrations are never run automatically at API startup.

## Required API configuration

- `ASPNETCORE_ENVIRONMENT=Production`
- `ConnectionStrings__LifeMateDb`
- `Authentication__Supabase__Issuer`
- `Authentication__Supabase__Audience=authenticated`
- `Authentication__Supabase__JwksUri`
- `Authentication__Supabase__RequireHttpsMetadata=true`
- `Security__Invitations__ContactPepper`
- `OpenApi__Enabled=false`

The database connection string and contact pepper are secrets. Rotate the
contact pepper only with an explicit invitation-invalidation plan because
pending contact-bound invitations depend on it.

## Pre-deployment

1. Build and test the exact commit.
2. Verify `dotnet ef migrations has-pending-model-changes` is clean.
3. Confirm the Supabase backup/PITR capability available on the selected plan.
4. Take or verify a recoverable database backup before schema changes.
5. Apply the reviewed migration as a separate controlled action.
6. Verify `/health/ready` against the target database.
7. Deploy the immutable API image.
8. Smoke-test authentication, bootstrap, patient isolation, invitation,
   revocation, dose reporting, and caregiver read access.

## Rollback

Application rollback means redeploying the prior immutable container image.
Do not automatically run EF `Down()` in production. If a migration introduced
an incompatible change, stop writes, assess data impact, and use the reviewed
forward-fix or backup-restore plan. Record the incident and timestamps.

## Privacy-safe logging

Logs may contain correlation IDs, route templates, status codes, latency, and
internal error classifications. Do not log access/refresh tokens, invitation
tokens, passwords, full email/phone contacts, medication names, dose text, or
free-form health notes.

## Beta incident priorities

- P0: cross-user disclosure, auth bypass, destructive data loss, leaked secret.
  Disable the affected path, revoke credentials, preserve evidence, and notify
  the founder immediately.
- P1: reminders broadly failing, API unavailable, reports not persisting.
  Pause new invitations and communicate the known limitation.
- P2: isolated UX or device issue. Record reproduction details and address in
  the next beta patch.

## Export and account deletion

Manual founder-assisted export/deletion remains a release blocker until a
tested authenticated self-service workflow is implemented. Never delete a
Supabase Auth user without first completing or safely scheduling deletion of
the corresponding application data.
