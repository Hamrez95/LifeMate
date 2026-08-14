# LifeMate reliability SLOs and observability runbook

These are engineering SLOs and launch gates for the current closed-beta runtime. They are **not a claim that production has already demonstrated this capacity**. Capacity remains whatever the latest protected staging load report proves.

## Runtime being measured

```text
WellMate / CareMate
        -> Supabase Auth
        -> lifemate-api Edge isolates
        -> Supavisor transaction pooler
        -> PostgreSQL

Optional work -> integration.outbox_messages -> lifemate-worker
Distributed request admission -> Redis/Upstash when shared rate limiting is required
```

## Telemetry contract

`lifemate-api` emits one bounded `lifemate.telemetry.window` aggregate per active Edge isolate approximately every 10 seconds. It does not emit request bodies, query strings, account identifiers, health values, emails, phone numbers, tokens or raw resource IDs.

Route labels replace UUID/numeric/opaque path segments with bounded placeholders. Every API response exposes `X-Correlation-Id`; failure bodies continue to include the same correlation ID where applicable.

Each telemetry window contains:

- request count and 2xx/3xx, controlled 429/503, ordinary 4xx and 5xx counts;
- a fixed server-duration histogram plus approximate p50/p95/p99 upper-bound buckets;
- bounded normalized route counts;
- current-isolate concurrency high-water marks;
- distributed rate-limiter source/health and last safe failure code;
- failure counts attributed to application, authentication, concurrency, database, idempotency or rate limiting.

Do not treat one isolate window as a global counter. Aggregate windows across the same release/service/time interval in the log backend. Counts are additive; histogram buckets are additive; high-water marks use `max`.

## Provisional SLOs inside the measured capacity envelope

| Signal | Target | Warning | Critical |
| --- | --- | --- | --- |
| Unexpected 5xx | < 0.5% | >= 0.5% for 5m | >= 1% for 5m |
| Read/API p95 | < 1500 ms | >= 1500 ms for 5m | >= 2500 ms for 5m |
| Read/API p99 | < 3000 ms | >= 3000 ms for 5m | >= 5000 ms for 5m |
| Critical-write duplicate/lost side effects | 0 | any suspected event | any confirmed event |
| Controlled overload | bounded 429/503 with `Retry-After` | sustained growth inside known capacity | growth plus latency/5xx cascade |
| Rate limiter | shared mode healthy in shared env | transient degraded event | degraded > 30s or unsafe config |
| DB connection usage | < 70% of configured max | >= 70% | >= 85% |
| DB waits/query timeouts | near zero | repeated waits/timeouts | sustained waits or timeout cascade |
| Outbox oldest ready age | < 120s | 120-899s | >= 900s |
| Dead-letter growth | no unexplained growth | new unexplained rows | sustained growth / critical identity event |

Valid authorization/validation 4xx responses are not service failures. A deliberate 429/503 is healthier than accepting excess work and cascading into timeouts, but sustained controlled overload **inside the last proven capacity envelope** is still a capacity/SLO incident and must be investigated.

## Staging performance evidence

Run the k6 harness and database-pressure collector together. Store both outputs with the exact commit, Edge release version, migration state and load profile.

```bash
# terminal 1 - local example
LOAD_PROFILE=ramp ACCESS_TOKEN='<synthetic-non-production-token>' \
  k6 run tools/load/lifemate-api-local.js

# terminal 2 - local database telemetry
DATABASE_URL='postgres://...' \
  tools/load/collect-runtime-pressure.sh
```

A protected remote/staging collector requires `LIFEMATE_OBSERVABILITY_TARGET=staging`. Never use a production healthcare database for destructive load generation.

The database collector records aggregate metadata only: configured max connections, current database/runtime-role connections, waits, long-running active queries and outbox queue counts/age. It does not select outbox payloads or healthcare tables.

## Triage: identify the limiting subsystem

**429 rises, limiter healthy, low DB pressure:** the configured per-subject/rate-class admission policy is the limiter. Confirm expected traffic shape before raising limits.

**Limiter state is degraded:** Redis/shared admission is unhealthy. The API deliberately falls back to conservative isolate-local limits. Investigate Redis latency/availability before increasing application capacity.

**503 `server_overloaded`, concurrency high-water at configured budget, DB healthy:** application concurrency is protecting the downstream. Find the expensive route mix and reduce route cost or add measured capacity; do not add an unbounded queue.

**503 `database_busy`, DB connection ratio/waits/query timeouts rise:** PostgreSQL/pooler/query capacity is the limiter. Stop increasing Edge concurrency, inspect slow/hot queries and connection headroom.

**API healthy, outbox lag grows:** optional downstream/worker throughput is the limiter. Keep request-path writes transactional; inspect event type/error code, dependency health and the outbox runbook before requeueing dead letters.

**5xx rises without admission/DB/worker pressure:** application regression. Use correlation IDs and the exact release version to find the error window and roll back if needed.

## Alert routing and emergency response

1. Confirm the exact release version and whether the event is within the latest measured capacity envelope.
2. Check status mix, p95/p99 histogram, subsystem failure counts, concurrency high-water and limiter state for the same 5-minute window.
3. Check database pressure samples and outbox lag.
4. If uncontrolled 5xx/timeout growth is occurring, reduce noncritical traffic/concurrency before scaling downstream blindly.
5. Never disable authorization, consent, idempotency or critical-write audit paths to recover capacity.
6. Never make Redis or the outbox the source of truth for medication/treatment/adherence state.
7. For queue incidents follow `docs/operations/outbox-worker.md`; do not bulk-requeue unknown dead letters.
8. Record start/end time, release, limiting subsystem, emergency changes and rollback/recovery evidence in the incident note.

## Privacy rules

- Correlation IDs are random request identifiers, not user identifiers.
- No raw URL query strings, UUID resource IDs, invitation tokens, request/response bodies or healthcare values enter reliability telemetry.
- Rate-limit keys remain one-way subject digests and are not emitted by observability.
- Database-pressure sampling is aggregate metadata only.
- Add a privacy review before introducing any external APM/session replay product.
