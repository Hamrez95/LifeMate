# Treatment / Dose legacy owner retirement runbook

This runbook covers staged retirement of `lifemate.treatment_plans.patient_user_id` and `lifemate.dose_occurrences.patient_user_id` under #393 / #289 / #217.

Source merge alone does **not** mutate production data, deploy an Edge runtime, remove legacy columns/indexes/FKs or alter actor/audit provenance. Live execution is separately protected and evidence-gated.

## Current architecture

- Treatment Plan ownership/authorization is canonical on `patient_person_id`.
- Dose occurrence ownership/materialization/self/caregiver reads are canonical on `patient_person_id`.
- Current runtime does not write `patient_user_id` for Treatment Plans or Dose Occurrences.
- `dose_adherence_events.actor_user_id` remains deliberate actor/idempotency provenance and is outside this owner-link scrub.
- Portable export selects Treatment/Dose datasets through canonical Person ownership and does not expose Person/Account/AppUser identifiers.

## Safety invariants

- Readiness is non-vacuous: at least one Treatment/Dose row must exist.
- Every Treatment/Dose `patient_person_id` must resolve to exactly one active Self Account with one active legacy AppUser during the staged rollback window.
- Any non-null legacy `patient_user_id` must match that unique active mapping.
- Every Dose occurrence must have the same `patient_person_id` as its Treatment Plan.
- Scrub/rehydration may change only `patient_user_id`; healthcare payloads, Person ownership, status, versions and timestamps are not rewritten.
- Apply uses optimistic row predicates and aborts on mapping/state drift.
- Operational output is counts only. AppUser/Account/Person/Treatment/Dose IDs and healthcare payloads are intentionally omitted.

## Live evidence snapshot

The source issue records a count-only snapshot collected before this tool was merged. Treat it only as historical evidence. **Always rerun protected readiness immediately before any live dry-run/apply.**

## Forward retirement order

Do not reverse this order.

1. Confirm exact reviewed `main` is deployed and current Treatment/Dose runtime remains Person-authoritative.
2. From protected exact `main`, private repository and protected `beta` Environment, run `readiness / dry-run`.
3. Require `ready=true`, zero missing/ambiguous/mismatched mappings and zero Dose/Treatment Person mismatches.
4. Run bounded `scrub / dry-run` and review count-only scope.
5. Run bounded `scrub / apply` with confirmation `SCRUB-TREATMENT-DOSE-OWNERS`; repeat while `hasMore=true`.
6. Rerun readiness and verify `linkedRows=0` while all rows remain mapped to canonical Person.
7. Exercise Treatment list, Dose list/report/caregiver access and portable export on the exact deployed runtime.
8. Keep legacy nullable columns and rollback tooling until a separate destructive-schema review proves no rollback dependency remains.

## Rollback / rehydration

Rehydration is an explicit rollback aid, not a normal runtime path.

1. Pause further scrub operations.
2. Run `rehydrate / dry-run` from the same protected exact-main workflow.
3. Confirm the active Self mapping is unique and consistent.
4. Run `rehydrate / apply` with confirmation `REHYDRATE-TREATMENT-DOSE-OWNERS` in bounded batches.
5. Re-run readiness and legacy rollback smoke before changing runtime versions.

If mapping becomes missing, ambiguous or inconsistent, **do not guess an AppUser ID and do not bypass the gate**. Resolve identity state through a separately reviewed recovery procedure.

## Explicit non-goals

- No production scrub from ordinary PR CI.
- No destructive legacy column/index/FK removal.
- No rewriting healthcare fields to make migration counts look clean.
- No removal of audit/adherence actor IDs whose meaning is actor provenance rather than healthcare ownership.
- No weakening caregiver relationship/consent authorization.

## Control-plane dependency

The live workflow intentionally fails closed unless it is executing exact `main` in a private repository on a protected ref with the protected `beta` Environment. While #210 is incomplete, source readiness can be merged and tested, but live retirement must not be represented as completed.
