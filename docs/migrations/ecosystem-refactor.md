# Ecosystem refactor migration plan

## Safety gate

The connected Supabase project contains 8 auth identities; most look test-like but not all can be proven synthetic from metadata. Therefore this refactor uses **non-destructive additive migration**. No reset/drop of business/auth data is permitted.

## Canonical migration ownership

Before this refactor, four EF Core migrations created the base `lifemate` schema while later SQL migrations evolved the live database. The live database therefore contained tables/columns absent from the EF model.

From this refactor forward, `supabase/migrations/*.sql` is the single production schema-evolution path and uses portable PostgreSQL. The four EF migrations are frozen historical artifacts; no new EF migration may evolve production schema.

A portable, idempotent reconstruction of the old EF-created base lives at `supabase/bootstrap/legacy_lifemate_baseline.sql`. It is **bootstrap only**, not a new production migration. Historical migration marker files retain the exact versions already recorded in the connected Supabase migration ledger; Supabase-only one-time infrastructure work is represented by a no-op ledger marker and its operational implementation lives under `supabase/infrastructure/` when it still matters. New ecosystem migration filenames also match the live Supabase versions exactly.

CI reconstructs a fresh PostgreSQL 17 database as:

```text
portable legacy bootstrap
  -> exact-version migration ledger in lexical order
  -> schema/authorization/privacy contracts
  -> idempotency rerun
```

This choice is driven by the observed live drift and portability requirement, not by a preference for Supabase-specific database features.

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

## Applied live migration ledger — ecosystem phase

The connected project records these exact versions/names:

- `20260806230837 ecosystem_data_foundation_20260807`
- `20260806231045 ecosystem_compatibility_policies_20260807`
- `20260806231112 person_ownership_compatibility_20260807`
- `20260806231133 authorization_entitlement_policy_20260807`
- `20260806231400 fix_entitlement_scope_semantics_20260807`
- `20260806231530 cover_ecosystem_foreign_keys_20260807`
- `20260806231838 harden_account_deletion_and_sync_20260807`
- `20260806231949 hot_query_person_indexes_20260807`

The repository filenames use those same versions so future migration tooling does not treat this refactor as an unrelated second chain.

## Compatibility and rollback

- Existing UUIDs and API response fields are preserved.
- No legacy ownership table/column is dropped in this phase.
- Backfills are deterministic and idempotent.
- Existing care relationships dual-write target access scopes and versioned consent.
- Existing health writers populate `person_id` through compatibility triggers only when an explicit Person is absent, allowing child/dependent ownership without an account.
- Database rollback is forward-only: disable new code/features and apply an explicit corrective migration. Do not run destructive Down migrations against live health data.
- Temporary dual-write is removed only after Edge + shared client use central capability/scope contracts and a rollback window has elapsed.

## Critical preconditions and verified results

- `dose_occurrences.treatment_schedule_id` had no FK; the live preflight found zero orphans, then the migration added the FK with a fail-closed orphan assertion.
- Contact blind indexes are not backfilled until a dedicated server-side hashing secret is available; legacy contact values remain temporarily for current invitation/profile contracts.
- Plaintext phone/email lookup indexes were removed from `lifemate.user_profiles`.
- Commercial/pharma export remains globally disabled.
- Health Connect and child/dependent commercial secondary use remain hard-denied by policy functions and contract tests.
