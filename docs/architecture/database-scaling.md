# Database scaling strategy

Target architecture is a modular monolith plus PostgreSQL. No early sharding or microservices.

## Event volume

Expected high-volume tables include dose occurrences/adherence events, audit records, measurements, notification attempts and future fitness/baby logs. Indexes are designed from query patterns, not added blindly to every foreign key.

## Dose occurrence generation

Occurrences are generated incrementally for bounded requested/worker windows. Never materialize an entire long treatment horizon. Default planning target is a configurable next-30-day window plus a bounded past window. Generation must remain idempotent through a unique `(treatment_schedule_id, scheduled_at_utc)` key.

## Pagination

Large timelines use keyset pagination, normally `(scheduled_at_utc, id)` or `(created_at_utc, id)`. OFFSET is limited to small administrative/result sets.

## Read models

Care dashboards use rebuildable projections such as daily adherence summaries instead of aggregating raw event history on every request. Transactional event tables remain the source of truth.

## Outbox

Important state transitions insert an `integration.outbox_messages` row in the same transaction. Push/SMS/projection/analytics work executes asynchronously and idempotently.

## Partitioning

Do not partition by default. Reassess a table when it approaches roughly 50-100 million rows, vacuum/index maintenance becomes material, or measured hot queries cannot meet targets with conventional indexing. A production partitioning change requires a shadow/backfill or attach-partition migration plan, validation of unique keys/foreign keys against the partition key, and rollback evidence.

## Connection management

The Edge runtime shares a deliberately small postgres.js pool (`max=1`, `prepare=false`) per isolate. Production DB URLs should use the appropriate Supabase pooler mode for short-lived/serverless workloads. .NET uses bounded Npgsql pooling and short transactions. Avoid parallel query fan-out per HTTP request and audit N+1 access with `pg_stat_statements`.

## Benchmarks

Repository benchmark tooling defines scalable synthetic data sets; it must run on disposable local PostgreSQL, never by inserting millions of rows into the connected Supabase project.

Initial engineering targets (not SLA):

- indexed simple DB query p95 < 50 ms
- dashboard projection DB p95 < 100 ms
- main API server-side p95 < 250 ms under reasonable test load

Every benchmark report must record dataset scale, PostgreSQL version, query, `EXPLAIN (ANALYZE, BUFFERS)` and environment. Tiny development data is not accepted as scale evidence.
