# LifeMate load and capacity testing

This directory contains the first repeatable capacity harness for the current closed-beta runtime:

```text
WellMate / CareMate
        -> Supabase Auth
        -> Supabase Edge Function: lifemate-api
        -> PostgreSQL
```

The first runner is deliberately **local-only**. It is intended to establish a baseline and catch obvious regressions without creating load against a shared or production service.

## Requirements

- k6 installed locally
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

## Output

Each run writes `load-summary.json` and prints the selected profile. The key metrics are:

- `lifemate_api_latency`: request latency trend;
- `unexpected_response_rate`: responses other than success or an explicit overload response;
- `controlled_overload_rate`: 429/503 responses, which are tracked separately because future overload protection should reject excess work deliberately instead of timing out or crashing.

The current provisional thresholds are:

- checks > 99%;
- unexpected response rate < 1%;
- p95 < 1500 ms;
- p99 < 3000 ms.

These thresholds are a starting contract, not a claim that current production capacity meets them.

## Safety rules

1. Never use real patient/caregiver accounts for capacity testing.
2. Never run destructive mutation scenarios against production.
3. Keep load-test data synthetic and disposable.
4. Record the exact commit, database shape, runtime configuration and test profile with every capacity result.
5. A performance test is incomplete if only RPS is captured. Record latency percentiles, status mix, Edge errors, PostgreSQL connection pressure and worker backlog at the same time.
6. A system that returns bounded 429/503 above capacity is healthier than one that accepts everything and collapses into timeouts.

## Next implementation steps

Issue #133 owns the capacity harness and baseline. Follow-up scale issues under Epic #132 add shared rate limiting, concurrency budgets, database protection, idempotency, queue safety and observability before a high-traffic campaign is considered ready.
