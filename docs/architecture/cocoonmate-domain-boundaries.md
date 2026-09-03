# ADR: CocoonMate domain boundaries, ownership and data classification

Status: **Accepted for Phase 0 implementation**  
Parent Epic: #776  
Closes architecture task: #777  
Verified against GitHub `main` at `cc8c775aebf5d204d13ad1b35e017ac15bfa7370` and the LIVE `lifemate` Supabase project on 2026-09-03.

## Decision

CocoonMate is a LifeMate product experience, not a parallel platform. It reuses the canonical LifeMate Account, Person, relationship, authorization, consent, Commerce, treatment, care-event and supported observation domains. Only facts that are genuinely pregnancy-specific belong to the new `pregnancy` bounded schema when Phase 0 persistence is introduced.

The permanent ownership model is:

- authentication principal: `identity.accounts.id`;
- healthcare data subject: `core.persons.id`;
- pregnancy owner/subject: the mother's `core.persons.id`;
- fetus: **not** a Person and never an account/person placeholder;
- child after an explicit birth outcome: a new `core.persons` row with `subject_category='Child'` plus the appropriate `network.person_relationships` parent/guardian relationship;
- product enrollment: `ecosystem.applications` + `ecosystem.app_enrollments`;
- commercial eligibility/entitlement: `commerce`;
- natural relationship: `network.person_relationships`;
- health-data authorization: `security.access_grants` + `security.access_grant_scopes` + typed `security.scope_catalog` entries;
- consent: `consent` and any approved subject/context binding, never inferred from relationship or payment.

No Cocoon implementation may collapse Account, Person, relationship, access, consent or entitlement into one flag or table.

## LIVE verification summary

The LIVE database was inspected before accepting this ADR.

Confirmed schema boundaries in use include `identity`, `core`, `ecosystem`, `network`, `security`, `consent`, `commerce`, `lifemate` and `care`. No `pregnancy` or `baby` schema currently exists.

Confirmed reusable platform objects include:

- `identity.accounts`;
- `core.persons`, `core.person_profiles`, `core.account_person_links`;
- `ecosystem.applications`, `ecosystem.app_enrollments`;
- `network.person_relationships`;
- `security.access_grants`, `security.access_grant_scopes`, `security.scope_catalog`;
- `consent.consent_records`, `consent.consent_events`, `consent.data_use_consents`;
- `commerce.products`, offers/subscriptions/entitlements and conversion infrastructure;
- `lifemate.medications`, `lifemate.treatment_plans`, `lifemate.treatment_schedules`, dose/adherence records;
- `lifemate.care_events`;
- `lifemate.health_observations`;
- `lifemate.women_health_lifecycle` and `lifemate.women_health_lifecycle_events`.

`core.persons.subject_category` already permits `Adult`, `Child`, `Dependent` and `Unknown`, so a newborn can enter the canonical Person model after birth without inventing a fetus/person surrogate during pregnancy.

The existing Women Health lifecycle supports:

`active -> paused_for_pregnancy -> postpartum_recovery -> resumable -> active`

and explicitly preserves historical cycle data. Cocoon pregnancy activation therefore coordinates with this lifecycle rather than replacing it.

## Product/domain lifecycle boundary

### Before pregnancy activation

The user may already have one LifeMate Account and Person, Women Health cycle data, treatments, care events, observations, relationships and entitlements. Cocoon must not copy any of those records.

### Active pregnancy

A new pregnancy episode belongs to the mother's Person. The pregnancy domain may own facts such as:

- episode lifecycle/outcome;
- canonical pregnancy dating inputs and dating revision history;
- pregnancy-specific clinical/context facts that do not belong to an existing shared domain;
- pregnancy-specific check-in or safety-rule inputs where a shared observation model is not semantically correct;
- narrow links from shared facts to the pregnancy episode when context is necessary.

Current gestational week/day is derived from canonical dating inputs and date/time rules. `current_week` is never a mutable source-of-truth column.

### Pregnancy outcome

A pregnancy ends through an explicit outcome transaction. Loss or other non-birth outcomes do not create a Child Person.

A delivered outcome may create exactly one Child Person per real child created by the delivery workflow, with explicit idempotency/concurrency protection. Child creation is a boundary transaction, not a prenatal placeholder conversion.

### Postpartum

Maternal postpartum facts remain person-scoped to the mother. Women Health return-to-cycle is an explicit lifecycle transition; it is not triggered merely because a pregnancy episode ended.

### Baby domain

The `baby` schema must not be created before the birth/child-identity boundary is proven. Baby-specific facts belong to the Child Person. Shared observations, appointments and treatment facts remain in their existing canonical domains.

A second future pregnancy creates a new pregnancy episode; it does not overwrite the first episode or reuse mutable pregnancy singleton state.

## Reuse matrix

| Concern | Canonical owner/schema | Cocoon use | Extension needed? | Prohibited duplicate |
|---|---|---|---|---|
| Auth/account | `identity.accounts` + Supabase Auth adapter | reuse current session/account | no Cocoon auth domain | `cocoon_users`, separate login DB/project |
| Person/profile | `core.persons`, `core.person_profiles`, `core.account_person_links` | mother is canonical Person; child created after birth | only shared profile fields when truly global | pregnancy profile copy, fetus Person |
| Relationship | `network.person_relationships` | identify partner/parent/caregiver relationship context | taxonomy only if a real missing relationship type is proven | household/member shortcuts or permission booleans on relationship |
| Access grant/scope | `security.access_grants`, `security.access_grant_scopes`, `security.scope_catalog` | explicit pregnancy/child sharing | add typed pregnancy/child scopes in #779 | relationship=permission, entitlement=permission |
| Consent | `consent` | bind explicit sharing/data-use consent where required | pregnancy-specific consent purpose/document only if policy requires | `pregnancy_consents` clone without platform integration |
| Commerce entitlement | `commerce` | Cocoon availability/paywall/conversion | reuse current Cocoon product and Period->Cocoon conversion | pregnancy billing/subscription tables |
| Medication/treatment | `lifemate.medications`, treatment plans/schedules/adherence | render/manage canonical records in Cocoon subject to access | optional narrow pregnancy-context link only if needed | `pregnancy_medications`, copied schedules |
| Appointment/care event | `lifemate.care_events` | pregnancy appointments/checkups use canonical events | optional episode context reference when necessary | `pregnancy_appointments` duplicate calendar |
| Health observations | `lifemate.health_observations` | weight/BP/glucose and other supported measurements | add supported categories/provenance only when semantically shared | `pregnancy_measurements` for already-supported facts |
| Women Health lifecycle | `lifemate.women_health_lifecycle` | pause period predictions/reminders; postpartum/resume coordination | safe transition hooks only | deleting/copying cycle history, Cocoon-owned period state machine |
| Notifications/reminders | shared local-first scheduling platform, #828/#830 | derive owner reminders from canonical local projection; remote sharing remains push | Cocoon reminder producers/routes | server/FCM-only owner dose/check-in reminder engine |
| Analytics/observability | approved LifeMate telemetry contract | product/reliability events only | Cocoon event namespace/allowlist | raw pregnancy facts in ordinary analytics/logs |
| Documents | future shared LifeMate health-document domain (#823+) | link pregnancy/postpartum/child context to canonical documents | shared document platform later | `pregnancy.documents` storage silo |
| Pregnancy | new bounded `pregnancy` schema | episode/dating/pregnancy-only facts | **yes, beginning #778** | generic JSON event dump, boolean pregnancy profile flag |
| Baby/child | `core.persons` for child identity; future `baby` bounded schema | only after birth | yes, after Gate #813/#814 | fetus Person, prenatal baby table as identity, Household aggregate |

## Facts that stay outside the pregnancy schema

Unless a later ADR demonstrates a genuine semantic mismatch, the following do **not** move into or get copied into pregnancy tables:

- account/contact/auth identity;
- Person/profile;
- relationship, access grant or consent state;
- subscriptions/entitlements/payments/conversion records;
- medications and treatment schedules;
- dose occurrences/adherence history;
- appointments/care events;
- supported generic health observations;
- Women Health cycle history;
- documents once the shared document domain exists.

Pregnancy may store an opaque foreign-key/context link where the fact requires episode association; ownership still remains with the canonical source domain.

## Timeline decision

Cocoon Records/Timeline is initially a server-composed read model over canonical sources. We do not persist a universal duplicate `pregnancy_events` stream merely to render a timeline.

A durable event table is justified only for an actual pregnancy-domain event with independent audit/lifecycle semantics, such as episode state transition or dating revision—not for copies of treatment, observation, appointment or document events.

## Pregnancy PHI and data classification

Pregnancy/reproductive state is sensitive health data. Product enrollment or commercial entitlement is never proof of pregnancy.

| Data class | Owner use | Explicit sharing | Admin/operations | Ordinary analytics/logs | Retention/deletion |
|---|---|---|---|---|---|
| pregnancy episode existence/status | owner-visible | only via explicit pregnancy scope | no ordinary raw User 360 field; aggregate operational metrics only | prohibited as identity-level dimension | follow health-record/account-deletion policy; preserve required episode history until policy deletion |
| LMP/EDD/dating inputs/revisions | owner-visible | explicit clinical/pregnancy scope only | no ordinary Admin visibility | prohibited | health-record retention/deletion; revisions preserved while record exists |
| gestational week/day | derived owner UI | scope-limited | no User 360 segmentation | do not emit as raw dimension | derived, not separately retained as mutable truth |
| pregnancy outcome/loss | owner-visible with respectful UX | only explicit high-sensitivity scope | no ordinary Admin/marketing exposure | prohibited | retained/deleted under health-record policy; never converted into growth audience |
| symptom/mood/check-in/private notes | owner-visible | category/scope-specific if supported | no ordinary Admin | raw values prohibited | domain retention; delete with approved data lifecycle |
| measurements | canonical observation rules | observation/pregnancy scope as applicable | no ordinary Admin health view | raw values prohibited | canonical observation retention/deletion |
| medications/treatments | canonical treatment rules | existing treatment scopes | no Cocoon-specific Admin shortcut | names/doses/times prohibited in ordinary telemetry | canonical treatment lifecycle |
| appointments/care events | canonical care-event rules | explicit scope | operational status only where privacy-approved | titles/health details prohibited | canonical care-event lifecycle |
| sharing grant metadata | owner can manage | grantee sees granted context | audit/operational metadata may be visible under capability | no reproductive inference | security/audit retention policy |
| app enrollment/entitlement | account/commercial state | not health-sharing data | may be visible for operations/Commerce | allowed only as product/commercial state; never infer pregnancy | Commerce/ecosystem policy |
| content/rule version | owner client uses version | not PHI | operationally visible | allowed | config/reference retention |

### Analytics and logging hard rule

Never log or emit ordinary product analytics containing raw or directly inferable LMP, EDD, gestational week, pregnancy outcome/loss, symptoms, measurements, medication names/doses, private notes or child health facts.

Technical telemetry may contain approved opaque request IDs, product/module version, error class, content/rule version, feature name and coarse success/failure state where that does not create a reproductive-health audience.

## Admin boundary

Ordinary Command Center/User 360 may show Cocoon application enrollment and commercial entitlement when required for support or Commerce. It must not show or infer:

- `pregnant = true`;
- pregnancy week/day;
- LMP/EDD;
- outcome/loss;
- symptoms/mood/measurements;
- medication or pregnancy appointment details;
- child growth/vaccine/milestone health facts.

Cocoon Admin operations use privacy-minimized read models tracked by `lifemate-admin#262` and the Admin Gate, not direct browser access to pregnancy tables.

## Cross-product invariants

For one mother concurrently using WellMate + Women Health + CocoonMate:

1. There is one Account/session and one canonical mother Person.
2. The same medication/treatment record is rendered in all authorized products; Cocoon does not create a pregnancy copy.
3. The same care event/appointment remains one canonical event.
4. The same supported observation remains one canonical observation.
5. Women Health cycle history is never deleted when pregnancy begins.
6. Pregnancy activation changes Women Health lifecycle only through its approved state machine and does not grant Cocoon entitlement or sharing permission.
7. Cocoon entitlement does not grant a partner/caregiver health access.
8. Existing partner/caregiver relationship does not disclose pregnancy until explicit grant/consent rules allow it.
9. Pregnancy end does not automatically resume cycle predictions; postpartum/cycle return is explicit.
10. A future child is a new Person after birth and does not reuse the mother's Person ID or a prenatal fetus identifier as identity.
11. Offline owner continuity follows #828: known schedules/content may execute locally, while cross-account sharing and authoritative entitlement/permission mutations remain online-authoritative.
12. Account switch/sign-out must isolate protected local health projections across all product modules.

## API and client boundary

Cocoon Flutter/product module uses the shared authenticated LifeMate client and the single reviewed `lifemate-api` healthcare runtime.

Cocoon must not:

- query pregnancy or shared health tables directly through Supabase Data API;
- receive service-role/database credentials;
- implement authorization only in Flutter;
- assume hidden client widgets are an access-control boundary.

The server returns subject/scope-shaped read models after enforcing Person ownership, grants/scopes, consent and product/domain policy.

## Portability

The pregnancy business schema remains portable PostgreSQL under `supabase/migrations`. Supabase Auth/Storage/provider mechanics remain infrastructure adapters. The new domain must not hardcode a direct client dependency on one Supabase origin or provider-specific business semantics.

## Consequences for the next Phase 0 tasks

### #778 pregnancy persistence

May create the `pregnancy` schema and typed episode/dating history only. It must reference the mother's `core.persons.id`, preserve dating revisions, enforce one active episode per mother and remain history-safe across loss/postpartum/second pregnancy.

### #779 authorization

Must extend the typed scope catalog and server authorization path; it must not add permission booleans to relationships or infer access from entitlement.

### #780 API contract

Must expose typed server-authoritative pregnancy contracts through `lifemate-api`/`lifemate_client` with idempotency, version/conflict semantics and PHI-safe failures/logging.

### Future Baby phase

No Baby table is added during Pregnancy Beta. Child Person creation is an explicit outcome boundary; only then may a bounded `baby` schema reference that Child Person.

## Rejected alternatives

### Generic Household aggregate
Rejected because family membership, natural relationship, authorization, consent and commercial access are different concepts. A Household shortcut would recreate ambiguity already removed by the ecosystem refactor.

### Fetus as Person
Rejected because prenatal state is an episode of the mother's pregnancy and does not yet represent the post-birth LifeMate data subject lifecycle. It also creates destructive merge/conversion problems for loss, multiples and subsequent pregnancy.

### Pregnancy copies of medications/appointments/measurements
Rejected because it creates divergent records, duplicate reminders and reconciliation problems across WellMate/Cocoon/CareMate.

### Pregnancy boolean on profile
Rejected because it cannot model history, multiple pregnancies, dating revisions, outcome, postpartum or loss safely.

### Entitlement-based health access
Rejected because payment/eligibility is not authorization or consent.

## Review checklist

- [x] Consistent with `ecosystem-data-model.md` and `data-boundaries.md`.
- [x] LIVE schema and migration chain checked on 2026-09-03.
- [x] No `pregnancy`/`baby` schema exists before the first real domain task.
- [x] Reuse matrix blocks duplicate medication, appointment and measurement storage.
- [x] Account/Person/Relationship/Permission/Consent/Entitlement are separate.
- [x] Loss, postpartum and future pregnancies fit without destructive rewrite.
- [x] Child identity begins after birth, not during pregnancy.
- [x] Sensitive pregnancy state is excluded from ordinary User 360/marketing segmentation.

## Change control

Any later Cocoon issue that needs to violate one of these boundaries must create an explicit ADR amendment with migration/security impact and evidence. Feature implementation must not silently redefine these ownership rules in UI or ad-hoc tables.
