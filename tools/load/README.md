# LifeMate load and capacity harness

Issue: #133 / Epic #132.

This directory contains the repeatable capacity tooling for the LifeMate foundation. It is intentionally split into a safe local/CI smoke path and a protected non-production staging path. **Production load testing is hard-blocked in code and workflow validation.**

## What exists

- `lifemate-api-local.js` — original localhost-only smoke harness retained for compatibility.
- `lifemate-api-capacity.js` — canonical multi-profile k6 runner with machine JSON + human summary.
- `collect-runtime-pressure.sh` + `runtime-pressure.sql` — PostgreSQL connection/wait/slow-query and outbox pressure sampling.
- `summarize-runtime-pressure.mjs` — compact machine-readable runtime pressure summary.
- `.github/workflows/performance-harness.yml` — credential-free local CI smoke and fail-closed guard tests.
- `.github/workflows/staging-capacity.yml` — protected manual staging execution and evidence upload.

## Local one-command smoke

Start any disposable localhost stub/API and run:

```bash
K6_NO_USAGE_REPORT=true \
LIFEMATE_LOAD_TARGET=local \
LOAD_PROFILE=smoke \
BASE_URL=http://127.0.0.1:18080 \
k6 run tools/load/lifemate-api-capacity.js
```

The runner writes:

- `load-summary.json` — full k6 machine result;
- `capacity-result.json` — compact LifeMate capacity schema containing profile, achieved RPS, dropped iterations, p50/p95/p99/max, 2xx/4xx/5xx/429/503 and reliability rates;
- a short human summary to stdout.

CI runs this smoke without any production/staging credential.

## Protected staging profiles

The staging workflow exposes only these bounded profiles:

| Profile | Workload | Bounded shape |
|---|---|---|
| `smoke` | health + authenticated basic read | 2 VU / 30s |
| `read-heavy` | home/dose/basic read mix | 100 arrival RPS / 2m |
| `ramp` | read mix | steps through 100 → 250 → 500 RPS over 10m |
| `spike` | read mix + recovery period | up to 2,000 RPS for 40s, then low-rate recovery |
| `soak` | read mix | 250 RPS / 60m |
| `care-mix` | relationship/invitation/dose reads | 100 RPS / 3m |
| `write-heavy` | critical dose adherence | 25 isolated VUs / 5m |
| `retry-storm` | critical adherence + controlled retry/replay | 25 isolated VUs / 3m |

The high numbers are test profiles, **not current capacity claims**.

### Required protected staging secrets

The GitHub `capacity-staging` environment must point to an isolated Supabase branch/project, never production:

- `STAGING_SUPABASE_PROJECT_REF`
- `STAGING_SUPABASE_URL`
- `STAGING_SUPABASE_PUBLISHABLE_KEY`
- `STAGING_LOAD_EMAIL`
- `STAGING_LOAD_PASSWORD`
- `STAGING_DATABASE_URL`
- `STAGING_DOSE_FIXTURES_JSON` for `write-heavy` / `retry-storm`

The workflow obtains a short-lived auth session at runtime. It does not store a long-lived user JWT.

For mutation profiles, `STAGING_DOSE_FIXTURES_JSON` must contain at least 25 synthetic dose occurrences, one per VU, for example:

```json
[
  {"id":"00000000-0000-4000-8000-000000000001","version":1,"status":"scheduled"}
]
```

Use only disposable synthetic staging data. Each VU owns one fixture so concurrent VUs do not race the same dose. Every logical adherence mutation uses a new `clientRequestId`/`Idempotency-Key`, then immediately retries the exact same logical mutation with the same key. The second attempt must return the idempotency replay header; missing replay evidence is a thresholded failure.

## Safety gates

`lifemate-api-capacity.js` refuses a remote target unless all of these hold:

1. `LIFEMATE_LOAD_TARGET=staging`;
2. `CONFIRM_STAGING_LOAD=LIFEMATE-STAGING-ONLY`;
3. the project ref is present and is **not** the LifeMate production ref;
4. the HTTPS API URL contains the staging project ref and does not contain the production ref;
5. a synthetic staging access token exists.

Mutation profiles additionally require `CONFIRM_SYNTHETIC_MUTATIONS=STAGING-SYNTHETIC-MUTATIONS` and at least 25 valid dose fixtures.

The database pressure collector applies the same production-ref block and requires the staging database URL to contain the same staging ref. Passing a production connection URL or production project ref fails before `psql` executes.

## Runtime pressure evidence

During a protected staging run, the workflow samples every five seconds and records:

- configured PostgreSQL max connections;
- total DB sessions;
- LifeMate Edge/worker runtime sessions;
- waiting runtime sessions;
- runtime queries active for more than one second;
- outbox queue metrics.

`runtime-pressure-summary.json` records the peak connection/wait/slow-query values and numeric outbox maxima. Raw NDJSON is retained with the k6 evidence artifact.

## Result interpretation

A threshold failure is useful evidence; it must not be hidden. The staging workflow uploads artifacts **before** enforcing the k6 exit code and `thresholdsPassed` flag, so a failed capacity run still preserves the bottleneck data.

Do not claim a supported user/RPS number from local CI, tiny production data, or a single successful spike. Scale-01 closes only after a protected staging run records the tested envelope, first bottleneck, overload behavior, recovery, DB pressure and critical-write idempotency evidence on the architecture being released.
