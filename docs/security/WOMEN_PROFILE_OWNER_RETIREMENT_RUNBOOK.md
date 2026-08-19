# Women Calendar profile owner retirement runbook

This runbook covers the staged retirement of `lifemate.women_calendar_profiles.owner_user_id` under #385 / #289 / #217.

Source merge alone does **not** mutate production data, run scrub/rehydration, deploy an Edge runtime, change secrets, or remove the legacy column/index. Live execution remains protected and separately evidence-gated.

## Safety invariants

- `owner_person_id` remains the canonical Women Calendar profile owner and primary key.
- Canonical API authorization, reads and exports remain Person-scoped.
- Normal Person-authoritative profile writes must not persist `owner_user_id`.
- Historical profile medical/cycle fields, `version`, and timestamps are not changed by scrub/rehydration; only the compatibility owner field is eligible.
- A legacy AppUser-only writer remains database-compatible until destructive retirement is separately approved.
- Readiness is fail-closed and non-vacuous: every existing profile must have exactly one active Self Account mapping with an active legacy AppUser and no mismatch/conflict.
- No identifiers are emitted by the operational workflow; summaries are count-only.

## Forward cutover order

Do not reverse this ordering.

1. **Deploy the Person-only runtime first** while the Person-primary schema from #384 remains rollback-compatible. The new runtime creates/updates profiles by `owner_person_id`, stores no profile AppUser compatibility owner, and writes profile audit resources as Person IDs.
2. Exercise profile create/read/update, Women Calendar authorization and portable export through the new runtime. Confirm profile audit insertion works when `owner_user_id` is NULL.
3. Only after the new runtime is confirmed live, apply the retirement migration that installs the INSERT-only canonical storage guard. Applying that trigger while an older Person runtime still depends on the returned `owner_user_id` for profile audit is not an approved rollout order.
4. Run the protected `women-profile-owner-retirement` workflow with `operation=readiness`, `mode=dry-run`. Stop on zero profiles, missing mappings, ambiguous Self mappings, legacy-owner mismatch, or rehydrate conflict.
5. Run `operation=scrub`, `mode=dry-run` with a bounded `max_profiles` and inspect the count-only summary.
6. Run bounded scrub apply with confirmation `SCRUB-WOMEN-PROFILE-OWNERS`. Repeat until `hasMore=false`; a final dry-run/apply should report zero eligible linked profiles.
7. Re-run Person-scoped profile read/update, Women Calendar authorization/caregiver boundaries and portable export. Confirm no AppUser/Account/Person identifiers are exposed by export payloads.
8. Record the exact main SHA and protected workflow evidence. Do not drop the compatibility column/index in this stage.

## Emergency rollback

An older backend reads Women Calendar profiles by AppUser, so **rehydrate before deploying an older backend**.

1. Stop additional scrub batches and keep the current Person runtime serving traffic where possible.
2. Run `operation=readiness`, `mode=dry-run`. Do not continue if mapping evidence is missing, ambiguous, mismatched or conflicting.
3. Run `operation=rehydrate`, `mode=dry-run` with a small bounded batch.
4. Run rehydrate apply with confirmation `REHYDRATE-WOMEN-PROFILE-OWNERS`. The tool restores only NULL compatibility owners from the unique active Self Account -> Person mapping and `Account.legacy_app_user_id`, with optimistic/conflict checks.
5. Repeat until `hasMore=false`, then verify an old AppUser-keyed profile read/update against the protected environment.
6. Only after successful rehydration evidence may an older backend be deployed.

## Forward-fix after rollback

1. Restore/deploy the current Person-only runtime.
2. Verify profile audit resources are Person IDs and new canonical creates store NULL compatibility owners.
3. Re-run readiness.
4. Resume bounded scrub dry-run/apply until no linked profiles remain.
5. Preserve the legacy column and uniqueness boundary until a later destructive-retirement issue proves no rollback/runtime dependency remains.

## Operational workflow guardrails

The manual workflow:

- runs only from exact `main`;
- requires a private repository and protected branch;
- uses the protected `beta` environment;
- reuses the identity migration database secret rather than embedding credentials;
- caps every mutation batch at 1000 profiles;
- requires explicit scrub/rehydrate confirmation strings for apply mode;
- emits only counts/booleans, never AppUser, Account or Person identifiers.

## Remaining blocker

Live cutover/protected-production evidence remains subject to #210 control-plane protection and owner evidence. This source slice does not claim that live activation has occurred.
