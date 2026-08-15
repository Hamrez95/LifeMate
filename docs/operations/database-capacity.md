# LifeMate PostgreSQL capacity contract

Issue: #136 / Epic #132

## Current measured state — 2026-08-15

The connected production Supabase project reported:

- PostgreSQL `max_connections = 60`;
- `superuser_reserved_connections = 3` and `reserved_connections = 0`;
- 12 total server sessions and 1 active session at the observation time;
- 0 `lifemate_edge_runtime` server sessions at that instant (a point-in-time observation, not proof of pooler mode);
- `lifemate_edge_runtime` has PostgreSQL `CONNECTION LIMIT 20`;
- `lifemate_worker_runtime` has PostgreSQL `CONNECTION LIMIT 5`;
- the canonical health-observation table has the owner FK index plus person/date/type read-path indexes;
- current production table sizes are still small: 3 health observations, 11 account-person links, 177 dose occurrences and 4 treatment plans.

These values are observations, not a capacity promise. The database is too small to infer high-load capacity from current query latency or planner choices. Connection headroom must be re-measured during the protected Scale-01 staging suite.

`pg_stat_statements` was enabled. For the restricted `lifemate_edge_runtime` role, normal health-history and calendar reads were sub-millisecond on average in the current small dataset. The slowest observed runtime statement was a bootstrap `app_users` upsert at roughly 103 ms mean across only two calls. No runtime statement in the sampled role data approached the 5 second statement-timeout budget. Migration/DDL statements run as privileged maintenance identities are not treated as application latency evidence.

## Edge connection policy

`lifemate-api` uses a single `postgres.js` connection per Edge isolate (`max: 1`). It disables prepared statements and applies bounded connection/query behavior:

- idle connection timeout: 5 seconds;
- connection establishment timeout: 10 seconds;
- maximum client connection lifetime: 10 minutes;
- PostgreSQL statement timeout: 5 seconds;
- lock timeout: 2 seconds;
- idle-in-transaction timeout: 5 seconds.

A request that cannot complete within these bounded database limits should fail and be handled by the API overload/retry contract instead of occupying a scarce connection indefinitely. The API also has a bounded concurrency gate so request fan-in is shed before one isolate can create unbounded database work.

## Server-side pooler requirement

For transient Edge/serverless traffic, the approved production path is Supabase transaction pooling on port 6543. Runtime configuration supports the fail-closed gate:

```text
LIFEMATE_REQUIRE_TRANSACTION_POOLER=true
```

The value is parsed strictly. Typos such as `tru` are rejected instead of silently becoming `false`. When the flag is enabled, startup rejects a direct or session-pooler URL.

The API and `lifemate-readiness` now expose only the safe transport classification (`transaction_pooler` or `direct_or_other`) plus whether the pooler requirement is enforced; no host, username, password or connection string is returned. Exact-main deployment verifies the restricted readiness role and records this transport evidence.

Before closing Scale-04, production must show both:

```text
databaseTransport = transaction_pooler
transactionPoolerRequired = true
```

Configure `LIFEMATE_DB_URL` with the restricted `lifemate_edge_runtime` identity on Supabase transaction pooling and set `LIFEMATE_REQUIRE_TRANSACTION_POOLER=true`. Do not replace the restricted role with `postgres`, service-role credentials or a migration identity.

## Schema protection

Migration `20260814070000_add_health_observation_owner_fk_index.sql` adds `lifemate.health_observations(owner_user_id)`. Live production verification on 2026-08-15 confirmed `ix_health_observations_owner_user_id` exists alongside the person/date/type indexes. Existing person-based indexes continue to serve health-history reads; the owner index prevents parent-user deletion/cascade checks from requiring a full table scan as the table grows.

The critical-query benchmark is maintained in `tools/benchmarks/critical_queries.sql`. Planner evidence on the current tiny production dataset must not be interpreted as a large-data benchmark; Scale-01 will execute the same query families against synthetic staging data at meaningful cardinality.

## Capacity thresholds before Foundation Closure

These are engineering gates, not claims that current production already supports them:

- exact-main Edge runtime must use transaction pooling on port 6543;
- application Edge pools remain `max: 1` per isolate;
- `lifemate_edge_runtime` server role remains capped at 20 connections unless a measured capacity change justifies another value;
- worker runtime remains independently capped at 5 connections;
- application statements remain bounded by the 5 second timeout and locks by 2 seconds;
- no measured normal hot-path query should routinely exceed 500 ms p95 in the staging capacity run;
- overload must produce bounded 429/503 before PostgreSQL connection exhaustion;
- the staging run must capture DB sessions, pool saturation/rejections, API p50/p95/p99 and recovery after load is removed.

## Capacity review checklist

Before a high-traffic campaign:

1. confirm transaction-pooler mode is enforced;
2. record `max_connections`, current connections, role connection limits and pooler headroom;
3. run the protected staging capacity suite;
4. capture `pg_stat_statements` and query plans for the hottest routes;
5. confirm no query routinely approaches the statement-timeout budget;
6. confirm 429/503 load shedding appears before connection exhaustion;
7. verify recovery after the load returns to the tested envelope;
8. do not remove INFO-only unused indexes solely to silence an advisor on a low-traffic database.
