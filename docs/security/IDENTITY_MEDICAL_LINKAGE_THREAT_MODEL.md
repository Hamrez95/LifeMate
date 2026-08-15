# Identity / Medical Linkage Threat Model

Status: **Foundation P0 / #217 — migration in progress**

This document defines exactly what LifeMate does and does not protect if an
attacker obtains a read-only logical PostgreSQL snapshot. It is deliberately
stricter than normal database-at-rest encryption: the assumed attacker can read
all dumped schemas and rows, but does not possess runtime/provider secrets kept
outside PostgreSQL and does not have a valid application session.

## Security property

LifeMate may claim database-breach identity separation only when a database-only
attacker cannot derive the mapping from a real/login identity to the healthcare
`Person` merely by joining dumped database rows or by hashing predictable public
identifiers.

`Account != AppUser != Person` remains an authorization/domain invariant, but
**different UUIDs or schemas are not themselves an unlinkability control**.

## Current production evidence — 2026-08-15

A metadata/count-only production audit was performed without copying identity
values into GitHub artifacts:

- 11 `auth.users` rows;
- 11 `lifemate.app_users` rows;
- 11 `identity.accounts` rows;
- 11 `identity.external_identities` rows;
- 11 active `core.account_person_links` rows;
- all 11 current `identity.external_identities.provider_subject` values directly
  match an `auth.users.id`;
- all 11 current `lifemate.app_users.auth_subject` values directly match an
  `auth.users.id`;
- all 11 accounts are reachable through the legacy AppUser bridge and an active
  Account -> Person link;
- `identity.contact_points` currently has no rows, so its hash/encryption fields
  do not protect the present identities;
- several healthcare tables still retain legacy `*_user_id` columns alongside
  `*_person_id` compatibility columns.

Therefore the current database is **not** unlinkable under this threat model.
A full logical read can currently follow direct joins from Supabase Auth identity
through legacy identity rows into person and healthcare state.

## Identifier classification

| Data | Current classification | Database-only risk |
| --- | --- | --- |
| `auth.users.id` | opaque provider identifier | linkable because copied into legacy/application identity rows |
| `auth.users.email/phone` | direct PII | plaintext/re-identification risk in a full auth-schema dump |
| `lifemate.app_users.auth_subject` | direct provider linkage | directly matches `auth.users.id` |
| `identity.external_identities.provider_subject` | direct provider linkage | directly matches current auth subject |
| `identity.accounts.id` | pseudonymous account identifier | becomes identifying through the direct bridge above |
| `core.account_person_links` | authorization/domain mapping | exposes Account -> Person once Account is identified |
| `Person` UUIDs | pseudonymous healthcare identifiers | safe only while no identifying join path is available |
| legacy healthcare `*_user_id` | compatibility identifiers | can bypass Person separation and directly link legacy AppUser to healthcare rows |
| profile email/phone/display metadata | PII / quasi-PII | may independently re-identify a person |
| timestamps/rare attributes | metadata | residual correlation risk even after direct joins are removed |

## Target architecture

```text
Supabase Auth subject
       |
       | HMAC-SHA256 with versioned key held OUTSIDE PostgreSQL
       v
opaque external_identity_token
       |
       v
Account -> AccountPersonLink -> Person -> healthcare data
```

The database stores only the opaque keyed lookup token for the external auth
subject. The key is supplied to the runtime from provider secret management and
must not be stored in PostgreSQL, Supabase Vault tables, database migrations,
GitHub source, logs or database backups.

A stolen database without that key may still reveal pseudonymous relationships,
care networks, timings and healthcare data. The intended property is narrower:
it must not contain a direct/raw login-identity join path that turns those
pseudonyms back into the corresponding authentication identity.

## Phase plan

### Phase 1 — additive token boundary

- add `identity.external_identity_tokens`, which has no raw-subject column;
- derive deterministic HMAC-SHA256 tokens in application code using an external
  versioned key;
- test token determinism, domain separation, key rotation and fail-closed key
  loading;
- preserve direct-client denial and retention-v2 purge behavior.

This phase is additive and **does not** satisfy the breach property by itself.

### Phase 2 — switch runtime identity resolution

- bootstrap/identity lookup uses keyed tokens as the authoritative auth -> Account
  resolver;
- dual-write/dual-read exists only for a bounded migration window;
- an authenticated account conflict fails closed;
- the old raw-provider bridge stops being created for new identities;
- key versioning supports old/new tokens during rotation without storing keys in
  the database.

### Phase 3 — remove raw identity PII/linkage from application schemas

- remove runtime dependence on `lifemate.app_users.auth_subject`;
- retire raw `identity.external_identities.provider_subject` storage;
- stop persisting raw auth email/phone in legacy profile storage where it is not
  required for healthcare operation; use an explicitly protected identity/contact
  boundary instead;
- verify account deletion removes active external-link tokens.

### Phase 4 — retire legacy healthcare user-ID joins

- prove every authoritative healthcare row has the correct Person ownership;
- move runtime reads/writes/authorization to Person/Account/AccessGrant semantics;
- remove or irreversibly de-identify legacy `*_user_id` compatibility columns only
  after fresh PostgreSQL, migration, rollback and live-role evidence is green;
- do not rewrite or delete production healthcare state without a reviewed backup
  and forward-fix plan.

### Phase 5 — database-only breach proof

Using synthetic fixtures only, produce a logical export that deliberately omits
all external key material and prove:

- protected login/provider plaintext cannot be recovered from the application
  schemas;
- no direct auth-subject/AppUser/user-ID join reaches healthcare rows;
- token lookup fails closed when the external key is unavailable;
- patient/caregiver/unrelated authorization and revocation remain unchanged;
- key rotation does not create duplicate accounts or orphan healthcare data.

## Key ownership and recovery

The identity-link key requires:

- at least 256 bits of unpredictable secret material;
- explicit integer key version;
- provider runtime secret storage outside PostgreSQL;
- no fallback to a database/Vault secret for this threat model;
- encrypted founder/operations backup outside the application database;
- documented rotation procedure with a bounded overlap period;
- recovery ownership tied to #211 without copying the key into database backup
  artifacts.

If the key is unavailable, identity-link operations fail closed. The system must
not silently fall back to raw auth IDs or create a second account for the same
identity.

## Residual risks

Even after direct linkage is removed, a database-only attacker may still infer
identity from rare combinations of timestamps, relationship graphs, free-text
notes, location-like metadata or outside knowledge. This design is
pseudonymization and compartmentalization, not anonymity.

Compromise of both PostgreSQL **and** the external runtime key restores the
identity-link capability. Compromise of an authenticated runtime/session is a
different threat and remains controlled by authorization, consent, rate limits,
audit and incident response.

## Release rule

Until phases 2–5 have evidence, LifeMate must not claim that a stolen database
cannot connect identity to medical data. #217 remains OPEN and #170 remains
`FOUNDATION_RELEASE_READY=NO`.
