# Identity / Medical Linkage Threat Model

Status: **Foundation P0 / #217 — source architecture advanced; live retirement still gated**

This document defines exactly what LifeMate does and does not protect if an
attacker obtains a read-only logical PostgreSQL snapshot. It is deliberately
stricter than normal database-at-rest encryption: the assumed attacker can read
all dumped schemas and rows, including provider-owned Auth tables when they are
part of the stolen database, but does not possess runtime/provider secrets kept
outside PostgreSQL and does not have a valid application session.

## Security property

LifeMate may claim database-breach identity separation only when a database-only
attacker cannot derive the mapping from a known real/login identity to the
healthcare `Person` merely by joining dumped database rows or by hashing
predictable public identifiers.

`Account != AppUser != Person` remains an authorization/domain invariant, but
**different UUIDs or schemas are not themselves an unlinkability control**.

The intended property is pseudonymization/key separation, not anonymity. A
database attacker may still see a pseudonymous Account -> Person -> healthcare
graph and may correlate metadata. What the protected boundary removes is the
raw/predictable login/contact value that makes that graph directly identifying.

## Live production evidence — 2026-08-19

A fresh metadata/count-only production audit was performed without copying any
identity values or healthcare payloads into GitHub artifacts.

Current live state is **not** compliant with the target database-only breach
property:

- 11 `auth.users` rows;
- 11 `lifemate.app_users` rows and all 11 still have non-null raw
  `auth_subject` values;
- 11 `identity.accounts` rows;
- 11 `identity.external_identities` rows and all 11 still have non-null raw
  `provider_subject` values;
- 11 active Self `core.account_person_links` rows;
- `identity.external_identity_tokens` is not yet present in the live schema;
- `identity.provider_identity_handles` is not yet present in the live schema;
- `identity.contact_points` exists but currently has 0 active rows;
- 11 legacy profile rows still contain raw email; raw legacy profile phone count
  is currently 0;
- legacy healthcare owner linkage is still present in live rows:
  - Medications: 4/4 `owner_user_id` non-null;
  - Treatment Plans: 4/4 `patient_user_id` non-null;
  - Dose Occurrences: 177/177 `patient_user_id` non-null;
  - Care Events: 4/4 `patient_user_id` non-null;
  - Health Observations: 3/3 `owner_user_id` non-null;
  - Women Calendar Profiles: 2/2 `owner_user_id` non-null;
  - Women Calendar Episodes: 1/1 `owner_user_id` non-null;
  - Women Calendar Daily Logs: 2/2 `owner_user_id` non-null;
  - Women Calendar Support Actions: 3/3 `patient_user_id` non-null.

Source migrations/runtime have advanced substantially beyond this live schema,
but the protected exact-main deployment/migration path intentionally remains
blocked while #210 is incomplete. Therefore **source CI success must not be
misrepresented as live unlinkability evidence**.

## Identifier classification

| Data | Target classification | Database-only risk |
| --- | --- | --- |
| `auth.users.id` | opaque provider identifier | provider-owned raw identity remains visible in a full provider DB dump, but must have no raw equality join into LifeMate Account state |
| `auth.users.email/phone` | direct PII | plaintext/re-identification risk inside the provider Auth domain; target separation prevents direct raw joins from those identities into LifeMate Person/healthcare state |
| `lifemate.app_users.auth_subject` | legacy direct provider linkage | target state is NULL/retired; any live non-null value defeats the narrow breach property |
| `identity.external_identities.provider_subject` | legacy direct provider linkage | target state is retired; any live raw row can directly identify Account |
| `identity.external_identity_tokens.subject_token` | keyed pseudonymous lookup token | safe against predictable recomputation only while the HMAC key remains outside PostgreSQL/backups |
| `identity.provider_identity_handles` | encrypted recovery handle | ciphertext remains sensitive metadata; provider Auth subject is recoverable only with the external envelope key |
| `identity.accounts.id` | pseudonymous account identifier | identifies Person only through the Account-Person graph; should not itself reveal login identity |
| `core.account_person_links` | authorization/domain mapping | intentionally reveals pseudonymous Account -> Person relationships inside the database |
| `Person` UUIDs | pseudonymous healthcare identifiers | not anonymous; safe from direct login mapping only while the identity boundary is protected |
| legacy healthcare `*_user_id` | compatibility identifiers | target state is NULL/retired because they can reconnect AppUser to healthcare rows |
| `identity.contact_points` hash/ciphertext | protected contact boundary | HMAC lookup + encrypted value; both hash/envelope keys must remain outside PostgreSQL |
| legacy profile email/phone | PII | target state is NULL/retired; plaintext defeats contact separation |
| audit/adherence actor IDs | provenance metadata | may expose activity correlation; retained only where actor/idempotency meaning is independently required and tracked as residual linkage |
| timestamps/rare/free-text attributes | metadata/quasi-identifiers | residual re-identification risk even after direct joins are removed |

## Target architecture

```text
Known Supabase Auth subject / contact value
       |
       | HMAC / envelope keys held OUTSIDE PostgreSQL
       v
opaque identity/contact token or ciphertext
       |
       v
Account -> AccountPersonLink -> Person -> healthcare data
```

The database stores opaque keyed lookup tokens and encrypted recovery/contact
envelopes. External HMAC/encryption keys are supplied to runtime from provider
secret management and must not be stored in PostgreSQL, Supabase database/Vault
tables used by this threat boundary, database migrations, Git source, logs or
database backup artifacts.

A stolen database without those keys may still reveal pseudonymous
relationships, care networks, timings and healthcare data. The intended property
is narrower: the database must not contain a direct/raw login/contact identifier
that turns those pseudonyms back into the corresponding authentication identity.

## Source architecture status

### Phase 1 — additive token boundary: implemented in source

- `identity.external_identity_tokens` has no raw-subject column;
- deterministic domain-separated HMAC-SHA256 tokens are produced in application
  code using an external versioned key;
- source tests cover determinism, fail-closed key loading, key rotation overlap
  and readiness;
- direct-client denial and retention/deletion behavior remain protected.

This phase alone does not satisfy the breach property.

### Phase 2 — token-authoritative runtime resolution: implemented in source

- token-only identity resolution is available and fail-closed;
- repeated bootstrap is canonical-token idempotent and cannot create a duplicate
  Account merely because raw identity state was retired;
- active/previous external-key overlap supports rotation without storing keys in
  PostgreSQL;
- ambiguity or key loss does not fall back to raw identity in token-only mode.

### Phase 3 — raw application identity/contact retirement: implemented in source

- raw `lifemate.app_users.auth_subject` retirement has source/runtime coverage;
- raw `identity.external_identities.provider_subject` storage is retired in the
  protected mode;
- encrypted provider recovery handles preserve revoke/delete capability without
  requiring raw provider subject storage;
- profile email/phone have encrypted ContactPoint dual-write/readiness/read-mode
  and raw-profile retirement paths;
- identity-link, provider-handle and ContactPoint encryption keys all have
  explicit rotation/readiness/recovery source contracts.

These controls are not yet all live in production because the protected
migration/deployment gate is not active.

### Phase 4 — legacy healthcare AppUser linkage retirement: source/recovery ready

- Medications, Treatment Plans, Dose Occurrences, Care Events, Health
  Observations and Women Calendar paths have been moved to canonical Person
  ownership in source;
- new canonical writes are prevented from recreating legacy owner linkage for
  the migrated paths;
- reversible bounded scrub/readiness/rehydration tooling exists where live
  historical compatibility rows remain;
- audit/adherence actor identifiers are not casually scrubbed when they carry
  independent actor/idempotency provenance;
- destructive column/index removal remains a later evidence-gated operation.

### Phase 5 — synthetic database-only breach proof: implemented by #395

A dedicated PostgreSQL test creates a synthetic post-retirement fixture with
unequal Auth subject, AppUser, Account and Person identifiers and representative
Person-owned healthcare state. The test then:

- verifies raw Auth/provider/profile-contact and representative healthcare
  compatibility identifiers are retired;
- verifies direct raw Auth/provider equality joins cannot reach the fixture's
  Person-owned healthcare row;
- verifies the pseudonymous Account -> Person -> healthcare graph is still
  visible and explicitly treats that as residual risk;
- runs `pg_dump --data-only` for LifeMate-owned application schemas **in memory
  only** and proves the dump contains none of the known raw Auth subject,
  provider subject, email, phone or synthetic external HMAC/encryption keys;
- verifies opaque token, encrypted provider handle and encrypted ContactPoint
  state still exists;
- removes identity-link key material from runtime configuration and proves
  protected identity lookup fails closed without creating another Account.

No logical dump from this proof is persisted or uploaded as a CI artifact.
Existing patient/caregiver/unrelated PostgreSQL role journeys continue to verify
that pseudonymization does not broaden authorization.

## What the synthetic proof does and does not prove

It proves that the **reviewed source target state** can satisfy the narrow direct
join/key-separation property using synthetic data and no external key material in
the database dump.

It does **not** prove that current production is already in that state. Live
production remains directly linkable until the exact reviewed migrations/runtime
are deployed through the protected control plane and the bounded live retirement
operations produce clean count-only evidence.

It also does not prove anonymity. A database-only attacker may still infer
identity from rare combinations of timestamps, relationship graphs, healthcare
patterns, free-text notes, locale/time-zone metadata or outside knowledge.

## Key ownership and recovery

Identity-link, provider-handle and ContactPoint keys require:

- at least 256 bits of unpredictable secret material in real environments;
- explicit integer key versions;
- provider/runtime secret storage outside PostgreSQL;
- no fallback to a database/Vault secret for the breach-separation claim;
- encrypted founder/operations recovery material outside the application
  database;
- documented bounded active/previous rotation windows;
- recovery ownership tied to #211/#226 without copying protective keys into
  database backup artifacts.

If a required key is unavailable, protected operations fail closed. The system
must not silently fall back to raw Auth IDs or create a second Account for the
same identity.

## Residual risks

Even after direct linkage is removed, a database-only attacker may still infer
identity from rare combinations of timestamps, relationship graphs, free-text
notes, location-like metadata, unusual healthcare patterns or outside knowledge.
This design is pseudonymization and compartmentalization, not anonymity.

Audit and adherence actor provenance may also remain linkable inside the
application database where the identifier has an independent security or
idempotency purpose. Such linkage must be inventoried and minimized rather than
mislabelled as healthcare ownership.

Compromise of both PostgreSQL **and** the relevant external runtime keys restores
protected lookup/decryption capability. Compromise of an authenticated
runtime/session is a different threat and remains controlled by authorization,
consent, rate limits, audit and incident response.

## Live closure requirements for #217

#217 remains OPEN until live evidence demonstrates the target state. At minimum:

1. #210 control-plane protection is complete so exact-main security migrations
   and runtime can be deployed only through the reviewed path;
2. the live identity token/provider-handle/contact migrations are applied and
   exact-main runtime uses the protected modes;
3. bounded live retirement readiness/scrub operations show raw application
   identity/contact and legacy healthcare owner linkage removed where intended;
4. live count-only re-audit confirms no direct raw login/contact -> Account ->
   Person -> healthcare equality path remains in LifeMate-owned schemas;
5. external key ownership/rotation/recovery and backup separation are evidenced
   without placing key material in PostgreSQL or backup artifacts;
6. residual actor/metadata linkage is accepted explicitly as the narrower
   pseudonymization risk, not represented as anonymity.

## Release rule

Until the live closure requirements above have evidence, LifeMate must not claim
that a stolen production database cannot connect identity to medical data.
#217 remains OPEN and #170 remains `FOUNDATION_RELEASE_READY=NO`.
