# LifeMate closed-beta backup, restore and monitoring

This runbook separates three guarantees that must not be confused:

1. **Logical database recoverability** — proven automatically in GitHub Actions against a second clean PostgreSQL cluster.
2. **Production managed backup availability** — supplied by the database provider and still requires provider-side evidence for the active Supabase project before inviting real families.
3. **Application readiness monitoring** — checks a public probe that uses the same restricted database role and required application objects as the real API, without reading user rows.

## Automated restore drill

`.github/workflows/postgres-restore-drill.yml` runs weekly, manually, and whenever the canonical PostgreSQL schema changes.

It:

- starts **two independent PostgreSQL 17.6 clusters** (source on 5432 and restore on 5433);
- applies `legacy_lifemate_baseline.sql` and every forward migration to the source;
- inserts a synthetic sentinel (never production/user data);
- creates a custom-format database dump **with ACLs preserved**;
- creates a separate password-free manifest for the two restricted cluster-global runtime roles;
- restores the role manifest and database archive into the independent clean cluster;
- proves the sentinel survived;
- proves critical LifeMate/identity/integration tables and account-lifecycle function survived;
- proves `lifemate.health_observations` still has RLS + FORCE RLS and the expected Edge policy;
- executes representative SELECT probes as `lifemate_edge_runtime` and `lifemate_worker_runtime` so restored grants are exercised, not just inspected;
- proves an unrelated role cannot read healthcare data;
- proves the restricted Edge role did not regain `BYPASSRLS`.

A green drill proves the repository + logical backup recovery path can reconstruct data, schema, ACL and runtime-role security boundaries in a clean PostgreSQL cluster. It does **not** prove that the hosted production project currently has a provider snapshot available.

## Production backup gate

Before opening the beta to real families, record evidence in #14 that the active Supabase project has a recoverable provider backup/snapshot according to the selected plan.

Minimum operational target for the closed beta:

- RPO target: 24 hours or better.
- RTO target: 4 hours or better for a small controlled beta.
- Never test destructive restore against the live project.
- Restore a provider snapshot into an isolated/staging project/database, then run the same critical contract checks used by the automated drill.
- Confirm account, Person, treatment, adherence, consent, audit and health-observation relationships after restore.
- Do not copy production PHI/PII into developer laptops or public CI artifacts.

## Production application readiness

`.github/workflows/production-health-monitor.yml` checks every 15 minutes and can also be run manually.

It calls only:

`GET /functions/v1/lifemate-readiness`

`lifemate-readiness` is intentionally separate from the lightweight `/health` liveness endpoint. On each request it obtains the restricted `lifemate_edge_runtime` credential from Vault and performs privacy-safe capability probes:

- active `wellmate` ecosystem application is queryable;
- `lifemate.health_observations` can be queried with a false predicate (grant/schema/RLS path is valid, no health row is read);
- `lifemate.dose_occurrences` can be queried with a false predicate;
- runtime is the restricted application role, not the bootstrap role.

Expected response fields are service metadata only:

- `status=ok`
- `database=application_ready`
- `role=restricted`
- `service=lifemate-readiness`
- deployed release version

The monitor does not authenticate as a user and does not request profile, treatment or health payloads. A non-200 response or failed restricted database capability fails the workflow.

The default URL points at the current LifeMate Supabase project. If infrastructure changes, set repository variable `LIFEMATE_READINESS_URL` rather than editing application code.

## Incident handling

When the readiness monitor fails:

1. confirm whether the failure is Edge runtime, Vault/runtime credential, PostgreSQL grants/RLS, missing migration, DNS/provider, or deployment-specific;
2. inspect Supabase Edge/Postgres logs using correlation/error codes only — never paste Authorization headers or health payloads into an issue;
3. if a new deployment caused the outage, roll the Edge function back to the last known healthy release before changing data;
4. if database integrity is in doubt, stop writes before attempting repair;
5. use provider backup/restore only in an isolated target first;
6. document start time, impact, root cause, recovery time and follow-up task without including patient data.

## Mobile crash visibility

Backend/application readiness monitoring is automated by this work. A dedicated external mobile crash-reporting vendor is intentionally not silently introduced because that requires a founder decision on processor/privacy terms and production credentials. Until one is selected, Flutter CI/on-device QA remain the mobile crash gate. This item stays explicit in #14 instead of being marked complete without real telemetry.
