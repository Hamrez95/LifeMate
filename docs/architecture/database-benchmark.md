# Database benchmark plan and evidence

Benchmark targets are engineering goals, not contractual SLA:

- simple indexed DB p95: < 50 ms
- rebuildable dashboard read model DB p95: < 100 ms
- main API server-side p95: < 250 ms under reasonable load

## Synthetic scale profiles

`tools/benchmarks/generate_ecosystem_dataset.sql` refuses to run unless the database name begins with `lifemate_benchmark`.

Full profile:

- 1,000,000 Accounts
- 1,200,000 Persons
- 2,000,000 care relationships/access grants
- 250,000 treatment plans/schedules
- 5,000,000 dose occurrences
- 5,000,000 adherence events
- 2,000,000 women-health daily logs
- 2,000,000 audit records

A 10k-account smoke profile runs on branch pushes when GitHub Actions are available. The 1M profile is a manual workflow choice so it does not consume CI time on every change.

## Critical query suite and expected indexes

| Query | Expected primary index/path |
|---|---|
| login identity lookup | unique `(provider, issuer, provider_subject)` |
| account -> person | account-person unique/link index |
| CareMate relationship list | current caregiver relationship index; later grants index |
| active access grants | `ix_access_grants_grantee_status_subject` + grant-scope PK |
| today's doses | `ix_dose_occurrences_person_local_date` |
| pending doses | `ix_dose_occurrences_person_status_time` |
| medication history | `ix_medications_owner_person_updated` |
| adherence timeline | existing occurrence + recorded-time index |
| daily dashboard | `care.daily_adherence_summary` PK |
| women-health recent logs | `ix_women_daily_owner_person_logged` |
| latest consent | `ix_consent_latest_subject_purpose` |
| audit resource history | `ix_audit_resource_created_desc` |

The exact `EXPLAIN (ANALYZE, BUFFERS)` statements are committed in `tools/benchmarks/critical_queries.sql`.

## Live migration smoke evidence — 2026-08-07

The connected Supabase database is deliberately tiny and is **not** a scale benchmark. These timings only prove the live schema/indexes are valid after migration:

| Query | Execution time | Observed path |
|---|---:|---|
| external identity lookup | 0.137 ms | unique external identity index scan |
| account -> self Person | 0.144 ms | account-person bitmap/index path |
| current CareMate relationship list | 3.488 ms | relationship index scan; tiny-set sort |
| active grant + scopes | 3.566 ms | grant filtering + scope PK; tiny live table favored seq scan for grant table |
| today's Person doses | 3.251 ms | `ix_dose_occurrences_person_local_date` bitmap index |
| pending Person doses | 1.520 ms | `ix_dose_occurrences_person_status_time` index-only scan |

Planning/cold-cache/catalog time is not included in the DB execution figures above. The full-scale profile must be executed before claiming million-user latency targets are met.

## Evidence limitation

GitHub did not schedule workflows for connector-authored branch/PR events in this session, so the full 1M benchmark has **not** been executed and no synthetic p95 claim is made. The benchmark workflow and guarded generator are committed and ready for a normal GitHub Actions dispatch.
