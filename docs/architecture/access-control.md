# Access control

LifeMate authorization is server-authoritative and uses distinct layers:

```text
Authentication
  + active Account
  + commercial Entitlement when the capability is gated
  + Person ownership OR an active contextual Access Grant
  + required Scope
  + applicable Consent/Relationship/Engagement policy
  = allow
```

A subscription or premium entitlement never grants access to another person's health data by itself.

## Scope naming

Scopes are lowercase dot-separated capabilities with an action suffix when applicable.

Examples:

- `treatment.medication.read`
- `treatment.medication.write`
- `treatment.plan.read`
- `treatment.plan.write`
- `treatment.adherence.read`
- `care.events.read`
- `care.events.write`
- `women_health.summary.read`
- `women_health.daily.read`
- `women_health.support.write`
- `pregnancy.summary.read`
- `baby.growth.read`
- `fitness.program.read`
- `fitness.program.write`
- `clinical.vitals.read`
- `clinical.notes.write`

## Grants

`security.access_grants` identifies subject person, grantee account, grantor person, status/window and an optional typed context such as a care relationship. `security.access_grant_scopes` stores the allowed scopes. Revoking a relationship revokes all grants tied to that relationship context immediately.

During migration, active care relationships receive scopes matching current behavior. `can_view_women_calendar=true` becomes `women_health.summary.read`. The legacy boolean stays temporarily for client compatibility and is dual-written until its removal gate is met.

## Central checks

Cross-person endpoints must call one access policy/resolver rather than reimplementing `relationship.status = Active`. Flutter only uses returned capability state to render UI; it is never the source of authorization truth.

## Private notes

Women-health private notes are owner-only. Neither a general care relationship nor `women_health.summary.read` authorizes them. A future sharing feature would require a new explicit scope and a separate, granular consent design.
