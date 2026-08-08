# LifeMate ecosystem data model

Status: architecture decision for `feat/ecosystem-data-foundation`  
Verified against GitHub `main` and the live Supabase schema on 2026-08-07.

## Current-state findings

The current model uses `lifemate.app_users` as both login account and health-data subject. The same identifier is referenced by treatment, care and women-health tables. `user_profiles` mixes presentation profile fields with phone/email PII. `care_relationships.can_view_women_calendar` mixes a human relationship with a permission. Consent is represented by a narrow `privacy_consents` table. The live database also contains additive SQL tables that are not represented by the EF Core model, so the repository currently has two schema-evolution paths.

A destructive reset is explicitly forbidden for this refactor because the connected Supabase project contains identities that are not all clearly synthetic.

## Before ERD

```mermaid
erDiagram
  APP_USERS ||--|| USER_PROFILES : has
  APP_USERS ||--o{ CARE_RELATIONSHIPS : patient
  APP_USERS ||--o{ CARE_RELATIONSHIPS : caregiver
  APP_USERS ||--o{ MEDICATIONS : owns
  APP_USERS ||--o{ TREATMENT_PLANS : patient
  MEDICATIONS ||--o{ TREATMENT_PLANS : uses
  TREATMENT_PLANS ||--o{ TREATMENT_SCHEDULES : schedules
  TREATMENT_PLANS ||--o{ DOSE_OCCURRENCES : creates
  DOSE_OCCURRENCES ||--o{ DOSE_ADHERENCE_EVENTS : history
  APP_USERS ||--o{ CARE_EVENTS : patient
  APP_USERS ||--o{ WOMEN_CALENDAR_PROFILES : owns
  APP_USERS ||--o{ WOMEN_CALENDAR_EPISODES : owns
  APP_USERS ||--o{ WOMEN_CALENDAR_DAILY_LOGS : owns
  APP_USERS ||--o{ PRIVACY_CONSENTS : grants
  APP_USERS ||--o{ AUDIT_LOGS : acts
```

## Target ERD

```mermaid
erDiagram
  ACCOUNT ||--o{ EXTERNAL_IDENTITY : authenticates
  ACCOUNT ||--o{ CONTACT_POINT : verifies
  ACCOUNT ||--o{ ACCOUNT_PERSON_LINK : links
  PERSON ||--o{ ACCOUNT_PERSON_LINK : subject
  PERSON ||--|| PERSON_PROFILE : profile
  ACCOUNT ||--o{ APP_ENROLLMENT : enrolls
  APPLICATION ||--o{ APP_ENROLLMENT : product

  PERSON ||--o{ PERSON_RELATIONSHIP : source
  PERSON ||--o{ PERSON_RELATIONSHIP : target
  PERSON ||--o{ ACCESS_GRANT : subject
  ACCOUNT ||--o{ ACCESS_GRANT : grantee
  ACCESS_GRANT ||--o{ ACCESS_GRANT_SCOPE : scopes
  SCOPE_CATALOG ||--o{ ACCESS_GRANT_SCOPE : defines

  PERSON ||--o{ CONSENT_RECORD : subject
  CONSENT_DOCUMENT ||--o{ CONSENT_RECORD : version
  CONSENT_RECORD ||--o{ CONSENT_EVENT : history
  PERSON ||--o{ DATA_USE_CONSENT : secondary_use

  PERSON ||--o{ MEDICATION : owns
  PERSON ||--o{ TREATMENT_PLAN : patient
  MEDICATION ||--o{ TREATMENT_PLAN : uses
  TREATMENT_PLAN ||--o{ TREATMENT_SCHEDULE : schedules
  TREATMENT_SCHEDULE ||--o{ DOSE_OCCURRENCE : generates
  DOSE_OCCURRENCE ||--o{ DOSE_ADHERENCE_EVENT : history
  PERSON ||--o{ CARE_EVENT : subject
  PERSON ||--o{ WOMEN_HEALTH_RECORD : owns

  PRODUCT ||--o{ PLAN : offers
  FEATURE ||--o{ PRODUCT_FEATURE : capability
  PRODUCT ||--o{ PRODUCT_FEATURE : contains
  PLAN ||--o{ PRICE : priced
  ACCOUNT ||--o{ SUBSCRIPTION : payer
  PERSON ||--o{ ENTITLEMENT : beneficiary
  FEATURE ||--o{ ENTITLEMENT : enables

  OUTBOX_MESSAGE }o--|| PERSON : aggregate_subject
  ANALYTICS_SOURCE_POLICY }o--|| PERSON : policy_subject
```

## Design rules

- `Account` is a stable LifeMate login principal. `Person` is the data subject. A person can exist without an account.
- Existing IDs are preserved during migration: each existing `app_users.id` is backfilled as both an account ID and the self-person ID. New accounts/persons are independent.
- Domain ownership migrates to `person_id`. Legacy `*_user_id` columns remain temporarily as compatibility columns.
- Natural family relationships remain separate from professional domain engagements. Future fitness/clinical roles belong to their own engagement/case tables, not a universal EAV relationship table.
- Permissions are represented by typed scopes, not booleans on relationships.
- Paid capabilities are represented by entitlements and never replace data authorization or consent.
- Future domains are not pre-created. Pregnancy, baby, fitness and clinical must follow these contracts when their first real feature is implemented.
- JSONB is reserved for bounded metadata/event payloads; primary domain facts stay typed and constrained.
