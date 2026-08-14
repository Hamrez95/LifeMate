# LifeMate capacity and overload contract

Status: initial engineering baseline for Epic #132 / Issue #133.

## Current runtime boundary

The current closed-beta application path is:

```text
WellMate / CareMate
        -> Supabase Auth + HTTPS
        -> Supabase Edge Function: lifemate-api
        -> server-side PostgreSQL connection
```

`backend-dotnet` remains the canonical domain/schema/migration reference; it is not a parallel beta runtime.

## Verified baseline observations — 2026-08-14

- Supabase project status: active/healthy, region `eu-west-1`.
- PostgreSQL reported `max_connections = 60`.
- At the observation time the database had 5 current connections and approximately 16 MB database size.
- `lifemate-api` deliberately shares one `postgres.js` client per Edge isolate with `max: 1`, `idle_timeout: 5`, `connect_timeout: 10`, and prepared statements disabled.
- The existing Edge rate limiter keeps counters in an in-memory Map; those counters are isolate-local and are not a distributed quota.
- Supabase Performance Advisor currently reports a foreign key on `lifemate.health_observations.owner_user_id` without a covering index. This should be evaluated with the real hot-query plan before/with the scale work.
- Recent `lifemate-readiness` log entries completed successfully but took roughly 3–6 seconds. That endpoint performs substantially more work than a normal lightweight readiness probe and is tracked separately in #141.

These facts describe the current environment. They are **not** a claim that the system supports a specific number of users or requests per second.

## Reliability rule

Capacity is the maximum load at which the service continues to perform useful work within the agreed latency/error envelope. Requests above that envelope should be rejected early and predictably rather than allowed to trigger database connection exhaustion, long queues, retry amplification, or cascading failures.

The desired overload behavior is therefore:

1. accept work while the tested capacity budget is available;
2. preserve critical treatment/adherence operations ahead of optional work;
3. return bounded `429 Too Many Requests` or `503 Service Unavailable` with retry guidance when capacity is unavailable;
4. recover automatically after demand returns below the safe envelope.

## Capacity record template

Every approved staging performance run must record:

- date/time and operator;
- exact Git commit and Edge release version;
- target environment and database compute tier;
- connection/pooler mode;
- synthetic dataset size;
- test profile and duration;
- offered RPS and achieved RPS;
- p50 / p95 / p99 latency;
- 2xx / 4xx / 5xx / 429 / 503 distribution;
- Edge execution errors and CPU/runtime limits if reported;
- PostgreSQL active connections and connection failures;
- slow-query evidence for the top routes;
- outbox queue depth/oldest-message age;
- limiter latency/error rate once distributed limiting is enabled;
- recovery time after the test returns to normal traffic.

## Provisional engineering targets

The high-scale numbers in Epic #132 are target test profiles, not the current baseline. They are intentionally not encoded in the local runner. Remote high-load testing must use an isolated staging target with explicit approval and hard duration/traffic caps.

Before a campaign receives a green capacity sign-off, we need measured evidence for:

- normal read mix;
- critical write mix;
- sudden traffic increase;
- sustained traffic;
- dependency slowdown;
- controlled overload response;
- client retry/backoff behavior;
- queue/backlog recovery;
- cold-cache behavior after caching is introduced.

## Source-of-truth and cache boundary

PostgreSQL remains authoritative for healthcare and relationship state. Redis may later be used for shared rate-limit counters and carefully approved cache entries, but it must not become the source of truth for medication, adherence, consent, relationship permissions or health observations.

## Release gate

A green functional CI build is not a capacity claim. Once the staging runner and telemetry are complete, the release checklist must include a recent capacity report and must fail closed when the current build materially regresses the established safe envelope.
