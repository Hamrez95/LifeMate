# LifeMate capacity and overload contract

Status: executable harness implemented; protected staging evidence still required for Issue #133 / Epic #132.

## Current runtime boundary

The current closed-beta application path is:

```text
WellMate / CareMate
        -> Supabase Auth + HTTPS
        -> Supabase Edge Function: lifemate-api
        -> restricted PostgreSQL runtime identity
```

`backend-dotnet` remains the canonical domain/schema/migration reference; it is not a parallel beta runtime.

## Verified engineering baseline — 2026-08-15

The baseline describes architecture and current measurements, **not a traffic-capacity claim**:

- Supabase production is healthy in `eu-west-1`.
- PostgreSQL `max_connections = 60`; `lifemate_edge_runtime` is capped at 20 connections and worker runtime at 5.
- Edge application SQL clients use `max: 1` connection per isolate, bounded connect/idle/query/lock timeouts and prepared statements disabled.
- Scale-02 source supports atomic Redis-over-HTTP shared admission with conservative local fallback, but production Redis is not yet provisioned/evidenced.
- Scale-04 source/release gates verify the restricted readiness identity and can require Supabase transaction pooling. Production exact-main deployment currently warns that transaction-pooler enforcement is still outstanding.
- The production database remains too small for a meaningful load claim. Current query-plan/`pg_stat_statements` observations are useful correctness baselines only.

## Reliability rule

Capacity is the maximum tested load at which the service continues to perform useful work within the agreed latency/error envelope. Requests above that envelope should be rejected early and predictably rather than allowed to trigger database connection exhaustion, long queues, retry amplification, duplicate critical mutations or cascading failures.

The desired overload behavior is:

1. accept useful work while the tested capacity budget is available;
2. preserve critical treatment/adherence operations ahead of optional work;
3. return bounded `429 Too Many Requests` or `503 Service Unavailable` with retry guidance when capacity is unavailable;
4. preserve idempotency when clients retry a critical medication report;
5. recover automatically after demand returns below the safe envelope.

## Executable harness

`tools/load/lifemate-api-capacity.js` is the canonical k6 runner. It produces both a full k6 JSON result and a compact LifeMate result with:

- achieved RPS and request count;
- dropped iterations;
- p50/p95/p99/max latency;
- 2xx/4xx/5xx/429/503 counts;
- unexpected-response, controlled-overload and uncontrolled-server-error rates;
- missing-correlation-ID rate;
- critical-write failure and idempotency-replay evidence;
- retry recovery rate.

`tools/load/collect-runtime-pressure.sh` samples PostgreSQL connection pressure, waiting runtime sessions, runtime queries over one second and aggregate outbox metrics. `summarize-runtime-pressure.mjs` produces a compact peak-pressure JSON summary.

The local CI smoke is credential-free. The protected `staging-capacity` workflow uses only an isolated staging project and a synthetic identity. Both the API runner and DB collector contain an explicit hard-coded block for the LifeMate production project ref.

## Bounded test profiles

These are test inputs, not accepted capacity numbers:

| Profile | Offered load / duration | Purpose |
|---|---|---|
| smoke | 2 VU / 30s | wiring, headers, summary contract |
| read-heavy | 100 arrival RPS / 2m | normal hot reads |
| ramp | 100 → 250 → 500 RPS over 10m | find first sustained bottleneck |
| spike | up to 2,000 RPS for 40s + recovery | overload/recovery behavior |
| soak | 250 RPS / 60m | sustained resource/queue drift |
| care-mix | 100 RPS / 3m | caregiver/relationship read mix |
| write-heavy | 25 isolated VUs / 5m | critical medication write correctness |
| retry-storm | 25 isolated VUs / 3m | duplicate/retry/idempotency behavior |

For adherence mutation profiles, every VU owns one disposable synthetic dose occurrence. Each logical mutation gets a new UUID request ID and idempotency key, then the exact same logical mutation is retried. The retry must be served as an idempotency replay; the harness treats missing replay evidence as a failure.

## Provisional thresholds

Until the first protected staging baseline establishes a measured safe envelope, the source harness uses these provisional quality thresholds:

- unexpected responses < 1%;
- uncontrolled server errors < 0.5%;
- missing correlation IDs < 0.1%;
- p95 < 1.5s;
- p99 < 3s;
- critical-write failures < 1%;
- missing idempotency replay evidence < 1%.

`429`/controlled `503` are measured separately from uncontrolled failures. A high controlled-overload rate can still mean the requested profile is above capacity even when the service is behaving safely. Offered RPS, achieved RPS and dropped iterations must therefore be reviewed together.

## Capacity evidence record

Every approved staging run must retain:

- exact Git commit and Edge release version;
- staging project ref/compute tier (never credentials);
- database transport and distributed-limiter mode;
- synthetic dataset / dose fixture count;
- selected profile and duration;
- offered and achieved RPS;
- p50/p95/p99/max latency;
- 2xx/4xx/5xx/429/503 and dropped iterations;
- PostgreSQL peak sessions, LifeMate runtime sessions, waits and >1s active queries;
- outbox backlog/age metrics;
- limiter degradation/latency evidence where available;
- critical write replay/duplicate evidence;
- recovery behavior after the spike/load is removed;
- first observed bottleneck.

A failed threshold run still uploads its machine evidence before the workflow fails. Do not suppress a capacity failure to obtain a green Actions badge.

## Scale-01 closure rule

Issue #133 remains open until the protected staging environment exists and the relevant profiles are actually executed against synthetic data. Source code, local CI and current tiny production observations are not enough.

The final capacity statement must say what was tested and where it first degraded. Do **not** translate a successful RPS profile into “supports tens of thousands of users” without a workload/concurrency model and repeated evidence.

## Source-of-truth and cache boundary

PostgreSQL remains authoritative for healthcare and relationship state. Redis may be used for shared admission counters and carefully approved cache entries, but it must not become the source of truth for medication, adherence, consent, relationship permissions or health observations.

## Release gate

A green functional CI build is not a capacity claim. Final stable Android remains blocked until the executable foundation gates are complete, including production pooler/distributed-admission configuration where required and a recent protected capacity report for the architecture being released.
