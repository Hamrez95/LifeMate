# LifeMate closed-beta backup, restore and monitoring

This runbook separates four guarantees that must not be confused:

1. **Logical database recoverability** — proven automatically in GitHub Actions against a second clean PostgreSQL cluster.
2. **Production managed backup availability** — supplied by the database provider and still requires provider-side evidence for the active Supabase project before inviting real families.
3. **Frequent production readiness** — a small public probe that checks Edge execution plus connectivity through the exact restricted application database role with one read-only query.
4. **Deep deployment verification** — comprehensive role/grant/RLS/capability tests executed in isolated CI, never on every monitoring interval.

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

## Frequent production application readiness

`.github/workflows/production-health-monitor.yml` checks every 15 minutes and can also be run manually.

It calls only:

`GET /functions/v1/lifemate-readiness`

The production readiness path is intentionally constant-cost. After obtaining/reusing the restricted runtime credential, each request performs exactly one small read-only query through `lifemate_edge_runtime`:

```sql
select current_user as role_name, 1::integer as dependency_ready;
```

This verifies that the Edge function can execute, the restricted database credential is usable, PostgreSQL/pooler connectivity works, and the request is not silently using the privileged bootstrap identity. It does **not** scan healthcare tables, inspect `pg_policies`, or write a synthetic probe row on every monitoring interval.

Expected response fields are service metadata only:

- `status=ok`
- `database=application_ready`
- `role=lifemate_edge_runtime`
- `service=lifemate-readiness`
- `mode=lightweight`
- bounded query duration metadata
- deployed release version

The monitor does not authenticate as a user and does not request profile, treatment or health payloads. A non-200 response, wrong role, non-lightweight mode or query timeout fails the workflow.

The default URL points at the current LifeMate Supabase project. If infrastructure changes, set repository variable `LIFEMATE_READINESS_URL` rather than editing application code.

## Deep deployment verification

The heavyweight capability verification was deliberately removed from the recurring production endpoint and retained in `.github/workflows/readiness-edge.yml`.

On pull requests/deployable changes, CI builds a disposable PostgreSQL 17.6 database, applies the canonical baseline plus every migration, configures `lifemate_edge_runtime`, and runs `deep_verification_test.ts` through that exact restricted role. The deep contract verifies:

- runtime role flags and the connection limit;
- active `wellmate` ecosystem registration;
- SELECT/INSERT/UPDATE/DELETE grants on `lifemate.health_observations`;
- the expected role-bound RLS policy;
- false-predicate access to health observations and dose occurrences without reading a user row;
- SELECT/INSERT/UPDATE/DELETE through FORCE RLS on `security.runtime_readiness_probe` using synthetic data only.

This preserves strong deployment-time security/capability evidence without turning routine monitoring into a repeated multi-query transaction against production.

## Incident handling

When the lightweight readiness monitor fails:

1. treat it first as an Edge/Vault/restricted-credential/pooler/PostgreSQL dependency failure, because the public probe no longer executes broad application-contract checks;
2. inspect Supabase Edge/Postgres logs using correlation/error codes only — never paste Authorization headers or health payloads into an issue;
3. if a new deployment caused the outage, roll the Edge function back to the last known healthy release before changing data;
4. if deeper grants/RLS/schema integrity is suspected, reproduce the deep readiness contract in isolated CI/staging rather than adding heavy checks back to the recurring production path;
5. if database integrity is in doubt, stop writes before attempting repair;
6. use provider backup/restore only in an isolated target first;
7. document start time, impact, root cause, recovery time and follow-up task without including patient data.

## Mobile crash visibility

Backend/application readiness monitoring is automated by this work. A dedicated external mobile crash-reporting vendor is intentionally not silently introduced because that requires a founder decision on processor/privacy terms and production credentials. Until one is selected, Flutter CI/on-device QA remain the mobile crash gate. This item stays explicit in #14 instead of being marked complete without real telemetry.
