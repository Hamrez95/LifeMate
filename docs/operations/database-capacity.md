# LifeMate PostgreSQL capacity contract

Issue: #136 / Epic #132

## Current measured state — 2026-08-14

The connected Supabase project reported:

- PostgreSQL `max_connections = 60`;
- 6 connections to the current database at the observation time;
- the canonical health-observation table already has read-path indexes on person/date/type;
- live schema did not have a leading `owner_user_id` index even though that column is a cascading foreign key.

These values are an observation, not a capacity promise. Database connection headroom must be re-measured before a campaign.

## Edge connection policy

`lifemate-api` uses a single `postgres.js` connection per Edge isolate (`max: 1`). It disables prepared statements and now also applies bounded connection/query behavior:

- idle connection timeout: 5 seconds;
- connection establishment timeout: 10 seconds;
- maximum client connection lifetime: 10 minutes;
- PostgreSQL statement timeout: 5 seconds;
- lock timeout: 2 seconds;
- idle-in-transaction timeout: 5 seconds.

A request that cannot complete within these bounded database limits should fail and be handled by the API overload/retry contract instead of occupying a scarce connection indefinitely.

## Server-side pooler requirement

For transient Edge/serverless traffic, the approved production path is Supabase transaction pooling on port 6543. Runtime configuration supports the gate:

```text
LIFEMATE_REQUIRE_TRANSACTION_POOLER=true
```

When that flag is enabled, startup rejects a direct or session-pooler URL. The runtime URL itself remains secret and must not be committed or logged.

Before enabling the gate in a shared environment, configure `LIFEMATE_DB_URL` with the restricted `lifemate_edge_runtime` identity on the transaction pooler. Do not replace the restricted role with `postgres`, service-role credentials, or a migration identity.

## Schema protection

Migration `20260814070000_add_health_observation_owner_fk_index.sql` adds a supporting index for `lifemate.health_observations.owner_user_id`. Existing person-based indexes continue to serve health-history reads; the new index prevents parent-user deletion/cascade checks from requiring a full table scan as the table grows.

## Capacity review checklist

Before a high-traffic campaign:

1. confirm transaction-pooler mode is enforced;
2. record `max_connections`, current connections, and pooler headroom;
3. run the protected staging capacity suite;
4. capture slow-query evidence and query plans for the hottest routes;
5. confirm no query routinely approaches the statement-timeout budget;
6. confirm 429/503 load shedding appears before connection exhaustion;
7. verify recovery after the load returns to the tested envelope.
