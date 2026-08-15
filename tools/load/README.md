# LifeMate load and capacity harness

Issue: #133 / Epic #132.

This directory contains the repeatable capacity tooling for the LifeMate foundation. It is intentionally split into a safe local/CI smoke path and a protected non-production staging path. **Production load testing is hard-blocked in code and workflow validation.**

## What exists

- `lifemate-api-local.js` — original localhost-only smoke harness retained for compatibility.
- `lifemate-api-capacity.js` — canonical multi-profile k6 runner with machine JSON + human summary.
- `collect-runtime-pressure.sh` + `runtime-pressure.sql` — PostgreSQL connection/wait/slow-query and outbox pressure sampling with explicit collector coverage status.
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
- `capacity-result.json` — compact LifeMate capacity schema containing profile, identity pool size, achieved RPS, dropped iterations, p50/p95/p99/max, 2xx/4xx/5xx/429/503 and reliability rates;
- a short human summary to stdout.

CI runs this smoke without any production/staging credential.

## Protected staging profiles

The staging workflow exposes only bounded profiles:

| Profile | Workload | Bounded shape | Minimum unique synthetic identities |
|---|---|---:|---:|
| `smoke` | health + authenticated basic read | 2 arrival RPS / 30s | 1 |
| `single-user-throttle` | intentional one-user limiter exercise | 10 arrival RPS / 60s | exactly 1 |
| `read-heavy` | home/dose/basic read mix | 100 arrival RPS / 2m | 20 |
| `ramp` | read mix | 100 → 250 → 500 RPS over 10m | 100 |
| `spike` | read mix + recovery | up to 2,000 RPS for 40s | 350 |
| `soak` | read mix | 250 RPS / 50m | 50 |
| `care-mix` | relationship/invitation/dose reads | 100 RPS / 3m | 25 |
| `write-heavy` | critical dose adherence | 25 paced isolated VUs / 5m | 25 |
| `retry-storm` | critical adherence + controlled retry/replay | 25 isolated VUs / 3m | 25 |

The high numbers are test profiles, **not current capacity claims**.

The hosted `soak` invocation is deliberately 50 minutes because current Supabase access tokens have a 60-minute lifetime and a token is acquired immediately before the run. A future 60+ minute hosted certification must rotate sessions between bounded segments; a tail of expired JWT `401` responses is not valid capacity evidence. Therefore the current 50-minute profile does **not** satisfy the Epic's 60-minute hosted soak target by itself.

### Synthetic identity pool

Capacity profiles must not reuse one authenticated account across all virtual users. LifeMate's shared application limiter is keyed by authenticated subject; a single token would measure the per-user limiter rather than API/database capacity and could make a run look healthy while mostly returning `429`.

The protected `capacity-staging` environment uses a pool of pre-created disposable accounts with one common synthetic password and deterministic emails:

```text
<STAGING_LOAD_EMAIL_PREFIX>+0001@<STAGING_LOAD_EMAIL_DOMAIN>
<STAGING_LOAD_EMAIL_PREFIX>+0002@<STAGING_LOAD_EMAIL_DOMAIN>
...
```

Required environment secrets are:

- `STAGING_SUPABASE_PROJECT_REF`
- `STAGING_SUPABASE_URL`
- `STAGING_SUPABASE_PUBLISHABLE_KEY`
- `STAGING_LOAD_EMAIL_PREFIX`
- `STAGING_LOAD_EMAIL_DOMAIN`
- `STAGING_LOAD_PASSWORD`
- `STAGING_DATABASE_URL`
- `STAGING_DOSE_FIXTURES_JSON` for `write-heavy` / `retry-storm`

The workflow signs in only the number of identities required by the selected profile, verifies that returned auth subjects are unique, masks the short-lived JWTs and keeps the generated session pool out of uploaded artifacts. `single-user-throttle` is the only profile intentionally constrained to one account.

For mutation profiles, `STAGING_DOSE_FIXTURES_JSON` must contain at least 25 synthetic dose occurrences. Every fixture must identify the authenticated owner using `subject` (or legacy `authUserId`), for example:

```json
[
  {
    "id": "00000000-0000-4000-8000-000000000001",
    "version": 1,
    "status": "scheduled",
    "subject": "00000000-0000-4000-8000-000000000101"
  }
]
```

The workflow fails before load if a fixture owner is absent from the authenticated pool. Each VU owns one fixture so concurrent VUs do not race the same dose. Every logical adherence mutation uses a new `clientRequestId`/`Idempotency-Key`, then immediately retries the exact same logical mutation with the same key. The second attempt must return the idempotency replay header; missing replay evidence is a thresholded failure. The normal `write-heavy` profile is paced so its own per-subject limiter is not the intended bottleneck; `retry-storm` is intentionally unpaced.

## Safety gates

`lifemate-api-capacity.js` refuses a remote target unless all of these hold:

1. `LIFEMATE_LOAD_TARGET=staging`;
2. `CONFIRM_STAGING_LOAD=LIFEMATE-STAGING-ONLY`;
3. the project ref is present and is **not** the LifeMate production ref;
4. the HTTPS API URL contains the staging project ref and does not contain the production ref;
5. the selected profile has the required number of unique synthetic auth sessions.

Mutation profiles additionally require `CONFIRM_SYNTHETIC_MUTATIONS=STAGING-SYNTHETIC-MUTATIONS` and at least 25 valid, owner-matched dose fixtures.

The database pressure collector applies the same production-ref block and requires the staging database URL to contain the same staging ref. Passing a production connection URL or production project ref fails before `psql` executes.

## Runtime pressure evidence

During a protected staging run, the workflow samples every five seconds and records:

- configured PostgreSQL max connections;
- total DB sessions;
- LifeMate Edge/worker runtime sessions;
- waiting runtime sessions;
- runtime queries active for more than one second;
- outbox queue metrics.

`runtime-pressure-status.json` is written even when the collector exits with an error. It records start/end time, sampling interval, sample count, requested duration, observed coverage, interruption state and exit code. The load and collector run in the same shell process so the workflow can capture the collector's real exit status. Final enforcement requires successful collector exit and pressure coverage through essentially the whole bounded k6 interval; a non-empty partial NDJSON file is not sufficient evidence.

`runtime-pressure-summary.json` records peak connection/wait/slow-query values and numeric outbox maxima. Raw NDJSON and collector status are retained with the k6 evidence artifact.

## Result interpretation

A threshold failure is useful evidence; it must not be hidden. For normal capacity profiles, excessive `429/503` is itself thresholded so a run cannot be reported green merely because overload responses were syntactically controlled. The dedicated `single-user-throttle` profile instead requires a measurable controlled-overload rate and proves the subject limiter is active.

The staging workflow uploads artifacts **before** enforcing the k6 exit code, threshold flag and pressure coverage flag, so a failed capacity run still preserves bottleneck data.

Do not claim a supported user/RPS number from local CI, tiny production data, or a single successful spike. Scale-01 closes only after a protected staging run records the tested envelope, first bottleneck, overload behavior, recovery, DB pressure and critical-write idempotency evidence on the architecture being released.
