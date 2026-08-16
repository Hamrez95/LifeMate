# LifeMate closed-beta privacy/legal review handoff

Status: **ENGINEERING REVIEW COMPLETE / HUMAN LEGAL APPROVAL OPEN**

Parent: Foundation #214. Engineering source task: #257.

This document is the review handoff from runtime truth to the Founder/legal reviewer. It does not create a legal basis, select a jurisdiction, approve a Privacy Notice/Terms document, or authorize public healthcare launch.

## 1. Data inventory and boundaries

| Domain | Current LifeMate data | Primary boundary / source |
| --- | --- | --- |
| Login identity | `identity.accounts`, external provider identity state/tokens, contact-point hashes/encrypted values, OTP challenge security metadata | Account is a login principal and is distinct from AppUser and Person. Raw provider/contact material is security-sensitive. |
| Person/profile | `core.persons`, `core.person_profiles`, `core.account_person_links` | A Person is the health/data subject. `Account -> account_person_links -> Person`; UUID equality is never a policy assumption. |
| Relationships/access | natural-person relationships, `security.access_grants`, scoped grants, care relationships/invitations | Relationship is not authorization. Active scoped access and current consent are evaluated separately. |
| Treatment/adherence | medications, treatment plans/schedules, dose occurrences/adherence events, care events | Health data is owned/authorized by Person/patient boundaries; caregiver reads/writes are not implied by account relationship alone. |
| Health/cycle | health observations and women-calendar profile/episodes/daily logs/support actions | Sensitive health/cycle data. Sharing requires an explicit current access/consent path; relationship alone is insufficient. |
| Consent | versioned consent documents/records/events and secondary-use consent | Grant/revoke/expiry/supersede are explicit facts. Absence of a current positive decision is denial. |
| Telemetry/audit | privacy-safe operational telemetry, security/audit evidence, correlation/release metadata | Routine operational evidence must not copy raw health payloads, contact/provider credentials or raw linked-person identifiers. |
| Operations | readiness, rate-limit/capacity, worker/outbox, incident and backup metadata | Operational evidence uses aggregate/status/run/SHA/timestamp metadata; production healthcare payloads are not incident evidence. |

Canonical structural source: `supabase/migrations/20260806230837_ecosystem_data_foundation_20260807.sql`.

## 2. Care sharing, consent and revocation

The current central authorization composition is fail closed:

- entitlement, scoped access grant and consent are separate facts;
- `security.can_access_person_feature(...)` requires the appropriate entitlement plus either self-link access or an active scope **and** a current `Granted` consent record;
- a revoked relationship is synchronized to a `Revoked` care-sharing consent state and consent history is retained as evidence;
- after revoke, a non-self caregiver no longer satisfies the current-consent predicate;
- no product copy may state or imply that simply being family/spouse/caregiver automatically exposes health or cycle data.

Canonical source: `supabase/migrations/20260806231133_authorization_entitlement_policy_20260807.sql` and `docs/privacy/consent-model.md`.

### Women/cycle data

Women/cycle information is **HIGHLY SENSITIVE** for launch review. The engineering rule is:

1. relationship alone is never permission;
2. access must be scope-bound and backed by a current explicit consent decision;
3. revocation removes the current authorization path;
4. secondary analytics/research/commercial consent is separate from care sharing;
5. no future women/cycle sharing surface may be enabled by a generic Terms acceptance or an account link.

Final user-facing opt-in copy and any narrower data-category split remain a human product/legal approval item below.

## 3. Self-service export

The authenticated export is portable JSON (`lifemate-portable-export-v1`), not a raw database dump.

Current included portable domains include the user's account/profile/enrollment state, owned treatment/adherence and health data, privacy consents, role/scope representation of care relationships without the other person's raw identifier, owned women-calendar data, and deletion-request history. Current bounds are maximum 20,000 rows per bounded dataset and 8 MiB serialized output; oversized exports fail rather than silently truncate.

Intentionally excluded security/privacy material includes:

- raw authentication/provider subjects;
- encrypted contact values/contact hashes;
- invitation token/contact hashes;
- raw identifiers belonging to linked people;
- internal audit/security logs;
- idempotency/cached-response keys;
- outbox transport records.

The API response path is `Cache-Control: no-store`. The client warns that copied JSON goes to the device clipboard.

Canonical contract: `docs/privacy/SELF_SERVICE_DATA_LIFECYCLE.md` plus `tools/operations/privacy_lifecycle_contract_test.ts` and runtime integration tests.

## 4. Account deletion and retention

A valid deletion request is asynchronous. The runtime immediately moves the identity to deletion-pending/disabled state and revokes/suspends current access paths; the client signs out. The worker then performs provider-auth/profile-storage deletion work before the retention-v2 database finalizer completes.

The finalizer removes or anonymizes directly owned health/women-calendar data, sign-in/contact/provider links and private operational material according to the reviewed retention-v2 contract. Minimum pseudonymous evidence may remain where needed for another person's shared-data integrity, revoked consent/security history, referential integrity/minimal operations, or a later legally approved retention obligation.

The current product wording deliberately does **not** promise immediate physical erasure of every row or invent a statutory retention period.

Canonical contract: `docs/privacy/ACCOUNT_DELETION_RETENTION.md`, `docs/privacy/SELF_SERVICE_DATA_LIFECYCLE.md`, `supabase/migrations/20260814215000_account_deletion_retention_v2.sql`, API/worker implementation and privacy lifecycle CI.

## 5. Telemetry, audit and support privacy boundary

Routine product/operations evidence must use the minimum metadata needed to diagnose a problem: category/status, UTC time, affected surface, exact release SHA, privacy-safe correlation identifier and aggregate counters/latency when applicable.

Do **not** move any of the following into GitHub, Trello, ordinary chat, routine telemetry or an external alert provider:

- raw medication/treatment/cycle/health payloads;
- access tokens, OTPs, passwords, recovery secrets or database credentials;
- email/phone values or encrypted contact material;
- raw provider subjects;
- Account/AppUser/Person identifiers unless a future reviewed exceptional support process explicitly requires and protects them.

Security/privacy/cross-user disclosure/data-loss reports follow `docs/operations/production-health-alerting.md`: suspected cross-user disclosure, consent bypass or unexplained healthcare data loss is SEV-1 until disproven. Technical incident handling is not a substitute for a jurisdiction-specific breach-notification decision.

### Privacy/support requests

Until legal review defines an exceptional identity-verification procedure, routine privacy/support intake may record only:

- request category;
- UTC received time;
- product/surface;
- privacy-safe incident/reference number;
- status/owner;
- whether the requester was directed to authenticated self-service export/deletion where applicable.

Do not invent a support-side identity-verification rule or request raw health data in order to process a privacy request. That procedure remains an approval item.

## 6. Secondary use / research / commercial analytics

Commercial/pharmaceutical analytics is **DISABLED by default**. Secondary-use consent is independent from care-sharing consent and general Terms acceptance.

Any future extraction must evaluate provenance, subject category, purpose and a current explicit opt-in before de-identification/aggregation, and also requires legal/platform-policy/jurisdiction approval. Current hard policy denies raw user-level health/PII, unrestricted partner queries, Health Connect sourced records for commercial/pharma export, and child/dependent commercial use unless a future narrowly reviewed policy permits it.

Canonical contract: `docs/privacy/secondary-data-use.md`, `docs/privacy/deidentification.md`, `docs/privacy/data-provenance.md`.

## 7. Approval register — release blocker

CI can verify that engineering behavior still matches this handoff. CI **cannot** change any row below to Approved.

| Review item | Version/date | Decision owner | Status | Evidence required before launch gate can close |
| --- | --- | --- | --- | --- |
| Closed-beta jurisdiction(s) | Not selected | Founder + legal/privacy reviewer | **OPEN / BLOCKING** | Named jurisdiction(s), applicable-law review and recorded launch limitations |
| Privacy Notice | Not approved | Founder + legal/privacy reviewer | **OPEN / BLOCKING** | Final version/date/hash or immutable approved copy matching this runtime behavior |
| Terms of Use | Not approved | Founder + legal/privacy reviewer | **OPEN / BLOCKING** | Final version/date/hash or immutable approved copy |
| Care-sharing consent copy | Not approved | Founder + legal/privacy reviewer | **OPEN / BLOCKING** | Final version/date and wording for grant/revoke/scope consequences |
| Women/cycle sensitive sharing copy | Not approved | Founder + legal/privacy reviewer | **OPEN / BLOCKING** | Separate explicit opt-in wording and approved scope/data-category boundary |
| Privacy/support contact | Not approved | Founder | **OPEN / BLOCKING** | Dedicated monitored contact/channel and ownership/escalation commitment |
| Exceptional privacy-request identity verification | Not approved | Legal/privacy reviewer | **OPEN / BLOCKING** | Jurisdiction-appropriate procedure; do not invent from engineering assumptions |
| Secondary research/commercial data use | Disabled | Founder + legal/privacy/platform reviewer | **DISABLED / NOT LAUNCH-AUTHORIZED** | Separate current consent design plus legal/platform/jurisdiction approval before enabling |

## 8. Release rule

Foundation #214 remains OPEN while any blocking approval-register item is OPEN. A green privacy CI run means **engineering contract consistency only**. It must never be interpreted as legal approval or permission to broaden the beta.

If approved legal/product wording conflicts with runtime behavior, change the runtime/contract or the wording through reviewed code and tests before launch; never weaken authorization, consent or retention safeguards merely to make policy text easier.
