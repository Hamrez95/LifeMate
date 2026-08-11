# LifeMate closed-beta backup, restore and monitoring

This runbook separates three different guarantees that must not be confused:

1. **Canonical schema recoverability** — proven automatically in GitHub Actions.
2. **Production managed backup availability** — supplied by the database provider and must be verified for the active Supabase plan/project before inviting real families.
3. **Service availability monitoring** — checks the public, non-user-data `/health` endpoint and its PostgreSQL dependency.

## Automated restore drill

`.github/workflows/postgres-restore-drill.yml` runs weekly, manually, and whenever the canonical PostgreSQL schema changes.

It:

- starts PostgreSQL 17.6;
- applies `legacy_lifemate_baseline.sql` and every forward migration in sorted order;
- inserts a synthetic sentinel (never production/user data);
- creates a custom-format `pg_dump`;
- restores that dump into a fresh database;
- proves the sentinel survived;
- proves critical LifeMate/identity/integration tables and account-lifecycle function survived;
- proves `lifemate.health_observations` still has RLS + FORCE RLS;
- proves the restricted Edge runtime role did not regain `BYPASSRLS`.

A green drill proves that the repository-owned canonical database state can be backed up and restored. It does **not** prove that the hosted production project currently has a provider snapshot available.

## Production backup gate

Before opening the beta to real families, record evidence in #14 that the active Supabase project has a recoverable provider backup/snapshot according to the selected plan.

Minimum operational target for the closed beta:

- RPO target: 24 hours or better.
- RTO target: 4 hours or better for a small controlled beta.
- Never test destructive restore against the live project.
- Restore a provider snapshot into an isolated/staging project/database, then run the same critical contract checks used by the automated drill.
- Confirm account, Person, treatment, adherence, consent, audit and health-observation relationships after restore.
- Do not copy production PHI/PII into developer laptops or public CI artifacts.

## Production health monitoring

`.github/workflows/production-health-monitor.yml` checks every 15 minutes and can also be run manually.

The monitor calls only:

`GET /functions/v1/lifemate-api/health`

Expected response fields are service metadata only:

- `status=ok`
- `database=ready`
- `service=lifemate-api`
- deployed release version

The monitor does not authenticate as a user and does not request profile, treatment or health data. A non-200 response, database-unready state or malformed health payload fails the workflow.

The default URL points at the current LifeMate Supabase project. If infrastructure changes, set repository variable `LIFEMATE_HEALTH_URL` rather than editing application code.

## Incident handling

When the health monitor fails:

1. confirm whether the failure is Edge runtime, PostgreSQL, DNS/provider, or deployment-specific;
2. inspect Supabase Edge/Postgres logs using correlation IDs only — never paste Authorization headers or request health payloads into an issue;
3. if a new deployment caused the outage, roll the Edge function back to the last known healthy release before changing data;
4. if database integrity is in doubt, stop writes before attempting repair;
5. use provider backup/restore only in an isolated target first;
6. document start time, impact, root cause, recovery time and follow-up task without including patient data.

## Mobile crash visibility

Backend health monitoring is now automated. A dedicated external mobile crash-reporting vendor is intentionally not silently introduced by this runbook because that requires a founder decision on processor/privacy terms and production credentials. Until one is selected, Flutter CI/on-device QA remain the mobile crash gate. This item should stay explicit in #14 instead of being marked complete without real telemetry.
