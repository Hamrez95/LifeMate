# LifeMate load and capacity testing

This directory contains the repeatable capacity harness for the current closed-beta runtime:

```text
WellMate / CareMate
        -> Supabase Auth
        -> Supabase Edge Function: lifemate-api
        -> PostgreSQL
```

The k6 runner is deliberately **local-only**. It establishes a baseline and catches obvious regressions without creating load against a shared or production service. Remote staging execution must use a separate protected runner with explicit duration/RPS caps and synthetic identities.

## Requirements

- k6 installed locally
- PostgreSQL `psql` when database-pressure telemetry is collected
- a local Supabase/Edge Function target
- optional non-production access token for authenticated read-mix testing

## Smoke

```bash
k6 run tools/load/lifemate-api-local.js
```

Without `ACCESS_TOKEN`, the harness exercises only `/health`.

## Authenticated read mix

```bash
BASE_URL=http://127.0.0.1:54321/functions/v1/lifemate-api \
ACCESS_TOKEN='<non-production-token>' \
k6 run tools/load/lifemate-api-local.js
```

The mix favors the read-heavy paths that currently fan into PostgreSQL:

- `GET /api/v1/home-snapshot`
- `GET /api/v1/dose-occurrences`
- `GET /api/v1/care/relationships`

## Local ramp

```bash
LOAD_PROFILE=ramp \
ACCESS_TOKEN='<non-production-token>' \
k6 run tools/load/lifemate-api-local.js
```

The initial ramp is intentionally capped at 100 arrivals/second. Larger remote/staging tests belong behind a protected, explicitly approved runner with a dedicated target, test identities, duration caps and an emergency stop. Do not repurpose this script to generate production traffic.

## Capture database and worker pressure at the same time

Local example:

```bash
DATABASE_URL='postgres://postgres:postgres@127.0.0.1:54322/postgres' \
INTERVAL_SECONDS=5 \
DURATION_SECONDS=120 \
bash tools/load/collect-runtime-pressure.sh
```

A remote read-only staging collector is allowed only with an explicit marker:

```bash
LIFEMATE_OBSERVABILITY_TARGET=staging \
DATABASE_URL='<protected-staging-database-url>' \
bash tools/load/collect-runtime-pressure.sh
```

The collector writes `runtime-pressure.ndjson`. It reads aggregate PostgreSQL connection/wait/query-age metadata plus outbox count/age metrics; it does **not** select healthcare rows or outbox payloads. The script intentionally has no `production` mode.

## Output and SLO evidence

Each k6 run writes `load-summary.json` and prints the selected profile. Key metrics are:

- `lifemate_api_latency`: client-observed API latency trend;
- `unexpected_response_rate`: responses other than success or explicit controlled overload;
- `controlled_overload_rate`: 429/503 responses;
- `server_error_rate`: uncontrolled 5xx (503 overload is tracked separately);
- `missing_correlation_id_rate`: responses missing the server correlation identifier.

The API also emits bounded structured `lifemate.telemetry.window` records from each active Edge isolate. Aggregate those windows by release/time interval to diagnose route/status/subsystem/concurrency/rate-limiter behavior. See `docs/operations/reliability-slos.md`.

The current provisional load thresholds are:

- checks > 99%;
- unexpected response rate < 1%;
- uncontrolled server error rate < 0.5%;
- missing correlation ID rate < 0.1%;
- p95 < 1500 ms;
- p99 < 3000 ms.

These thresholds are a starting engineering contract, not a claim that current production capacity meets them.

## Safety rules

1. Never use real patient/caregiver accounts for capacity testing.
2. Never run destructive mutation scenarios against production.
3. Keep load-test data synthetic and disposable.
4. Record the exact commit, Edge release version, database migration state, limiter mode and test profile with every result.
5. A performance test is incomplete if only RPS is captured. Record latency percentiles, status mix, Edge telemetry, PostgreSQL connection pressure and worker backlog together.
6. A system that returns bounded 429/503 above capacity is healthier than one that accepts everything and collapses into timeouts.
7. Do not raise API concurrency or rate limits while DB pressure is already the limiting subsystem.

## Related scale work

Epic #132 owns viral-launch resilience. The capacity harness (#133), shared admission control (#134), concurrency budgets (#135), DB protection (#136), idempotency (#137), queue safety (#138) and observability/SLOs (#140) are designed to produce one evidence chain rather than independent optimizations.
