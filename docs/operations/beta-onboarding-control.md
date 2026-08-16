# Closed-beta onboarding control

Parent: Foundation #216 / Ops #244.

## Purpose

LifeMate can pause **new application onboarding** without deploying new code and without depending on Supabase-specific APIs. The control is stored in LifeMate-owned PostgreSQL schema `security.runtime_controls` under the key `new_user_onboarding`.

This is an application-bootstrap gate, not an identity-provider kill switch. A provider Auth account may still be created while this control is paused; that subject cannot become a new LifeMate `AppUser` until onboarding is resumed. Existing AppUsers continue normal authenticated flows and can safely retry the idempotent bootstrap path.

## Ownership and permissions

- Founder/release operator decides when onboarding is paused or resumed during the closed beta.
- Only an approved migration/operator database identity may mutate the control.
- `lifemate_edge_runtime` has read-only visibility of the single operational row and cannot update it.
- `anon` and `authenticated` database roles receive no access.
- Do not add a public HTTP mutation endpoint for this switch.

## Pause onboarding

Run with an approved operator/admin PostgreSQL identity. Never place database credentials in the SQL file, issue, PR, shell history or task arguments.

```sql
begin;

update security.runtime_controls
set enabled = false,
    note = 'Closed-beta onboarding paused by operator'
where control_key = 'new_user_onboarding';

select control_key, enabled, updated_at_utc
from security.runtime_controls
where control_key = 'new_user_onboarding';

commit;
```

Expected application effect:

- a genuinely new `lifemate.app_users` insert is rejected at the database boundary with a controlled temporary-unavailable database condition;
- the API converts that condition to its existing controlled 503 `database_busy` response and does not leak database details;
- an existing Auth subject already mapped to an AppUser can continue the idempotent `INSERT ... ON CONFLICT(auth_subject)` bootstrap path;
- existing patient/caregiver/consent/healthcare authorization behavior is unchanged.

## Resume onboarding

```sql
begin;

update security.runtime_controls
set enabled = true,
    note = 'Closed-beta onboarding resumed by operator'
where control_key = 'new_user_onboarding';

select control_key, enabled, updated_at_utc
from security.runtime_controls
where control_key = 'new_user_onboarding';

commit;
```

After resuming, verify with a synthetic/non-production test identity through the normal bootstrap path. Do not use real healthcare data for control verification.

## When to pause

Pause new onboarding for an unresolved incident involving any of the following:

- suspected cross-user disclosure or authorization/consent regression;
- unrecoverable or unexplained healthcare data loss;
- systemic reminder/adherence reliability failure;
- uncontrolled availability failure outside the measured capacity envelope;
- compromised release/signing/production-control path;
- recovery/backup incident where adding more healthcare state would increase risk.

The operator may also disable provider-side signup as defense in depth when appropriate, but this runbook remains valid after a future PostgreSQL provider migration.

## Recovery and audit evidence

Record only non-sensitive evidence: UTC pause/resume time, incident/reference number, deployed SHA, operator role, and whether the synthetic post-resume bootstrap succeeded. Never copy tokens, emails, phone numbers, Account/AppUser/Person identifiers, database URLs or health payloads into operational evidence.
