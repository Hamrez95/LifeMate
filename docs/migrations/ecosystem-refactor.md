# Ecosystem refactor migration plan

## Safety gate

The connected Supabase project contains 8 auth identities; most look test-like but not all can be proven synthetic from metadata. Therefore this refactor uses **non-destructive additive migration**. No reset/drop of business/auth data is permitted.

## Canonical migration ownership

Current reality is split: four historical EF Core migrations create the base `lifemate` schema and later `supabase/migrations/*.sql` files add live production schema. The live database has tables/columns absent from the EF model.

Target: `supabase/migrations/*.sql` becomes the single forward schema-evolution path, using portable PostgreSQL SQL. Existing EF migrations are frozen historical/bootstrap artifacts and .NET remains a domain/reference implementation, but no new EF migration may evolve production schema. CI applies SQL only to fresh PostgreSQL and detects drift.

This choice is driven by the existing live drift and portability requirement, not by a preference for Supabase-specific database features.

## Phases

1. Audit and record current schema, constraints, grants, API contracts and data-safety gate.
2. Add account/person/application foundation and backfill every existing user as Account + Self Person.
3. Add provider-independent external identity/contact/OTP structures without changing current login contract.
4. Add scoped access grants + first-class consent; backfill current care access and women summary scope.
5. Add `person_id` ownership to treatment/care/women-health tables, retaining legacy columns temporarily.
6. Make Edge cross-person authorization use central scopes; dual-write the legacy women permission during transition.
7. Add provenance, restricted-source policy, commerce/entitlement foundation, outbox and read-model foundation.
8. Add targeted indexes and missing referential constraints; benchmark query plans.
9. Migrate Flutter/shared client to capabilities without making it authoritative.
10. Remove compatibility fields only after release telemetry and rollback window prove no dependency.

## Compatibility and rollback

- Existing UUIDs and API response fields are preserved.
- No legacy ownership column is dropped in this PR.
- Backfills are deterministic and idempotent.
- New authorization data is seeded from current active relationships before Edge code requires it.
- Database rollback is forward-only: disable new code/features and apply an explicit corrective migration. Do not run destructive Down migrations against live health data.
- Temporary dual-write has a removal issue/date once all clients consume scope-based permissions.

## Critical preconditions

- Before adding the missing `dose_occurrences.treatment_schedule_id` FK, assert zero orphan rows. Migration fails closed if any exist.
- Never backfill contact blind indexes without the dedicated server hashing secret; keep legacy contact data until a controlled application backfill can run.
- Secondary commercial export remains disabled throughout this migration.
