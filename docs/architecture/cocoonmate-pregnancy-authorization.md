# CocoonMate pregnancy authorization

Pregnancy authorization is server-authoritative and fail-closed.

`Account -> Person` remains the identity boundary. `network.person_relationships`, `security.access_grants`, consent and commerce are distinct state machines. Neither a natural relationship nor an entitlement grants pregnancy health-data access.

## Canonical sharing context

Cross-person pregnancy grants use:

- `subject_person_id`: mother Person;
- `grantee_account_id`: caller Account;
- `context_type`: `pregnancy_episode`;
- `context_id`: canonical `pregnancy.episodes.id`;
- one or more exact `security.access_grant_scopes` entries;
- an active `consent.consent_records` row with `purpose=pregnancy_sharing` and `scope_key=pregnancy_episode:<episode-id>`.

Shared access is limited to an active pregnancy episode. Ended pregnancy history is owner-private until a separately reviewed historical-sharing contract exists. Future child access is a separate authorization decision and is never inherited from a pregnancy grant.

## Scope catalog

| Scope | Meaning | Cross-person grantable? |
| --- | --- | --- |
| `pregnancy.summary.read` | Bounded pregnancy summary/current gestational week/day | Yes |
| `pregnancy.calendar.read` | Pregnancy plan/calendar context | Yes |
| `pregnancy.observations.read` | Pregnancy-context health observations | Yes |
| `pregnancy.appointments.read` | Pregnancy-context appointments | Yes |
| `pregnancy.medications.read` | Medication context when explicitly shared | Yes |
| `pregnancy.documents.read` | Future pregnancy documents | Yes |
| `pregnancy.support.write` | Explicitly permitted collaborative check-in/support input | Yes |
| `pregnancy.owner.manage` | Lifecycle, dating, sharing and owner administration | **No — owner only** |

There is deliberately no `pregnancy.all` scope. A narrow scope never implies a broader resource.

## Authorization matrix

| Actor | Resource/action | Relationship prerequisite | Explicit consent | Exact access scope | Entitlement grants PHI? | Result |
| --- | --- | --- | --- | --- | --- | --- |
| Mother owner Account | Own pregnancy read/manage | No | No sharing consent required | Owner is authorized by active Self link | No | Allow |
| Partner | Shared summary | No implicit permission from relationship | Yes | `pregnancy.summary.read` | No | Allow only with active episode-scoped grant + consent |
| Partner | Observations when only summary was granted | No | Yes | Missing `pregnancy.observations.read` | No | Deny |
| Caregiver/other trusted Account | Any shared pregnancy resource | Relationship alone is insufficient | Yes | Exact resource scope | No | Allow only with explicit grant + consent |
| Any non-owner | `pregnancy.owner.manage` | Irrelevant | Irrelevant | Even a malformed grant must not authorize | No | Deny |
| Unrelated Account with known UUIDs | Any pregnancy resource | None | None | None | No | Deny |
| Account with commercial entitlement only | Any pregnancy PHI | Irrelevant | Missing | Missing | **Never** | Deny |
| Revoked/expired grant or consent | Previously shared resource | Irrelevant | Revoked/expired | Revoked/expired | No | Deny on next server check |
| Non-owner after episode ends | Pregnancy history | Irrelevant | Existing sharing consent is insufficient | Existing scope is insufficient | No | Deny |
| Future child Person | Child resource | Separate model | Separate consent | Separate child scope | No | No inheritance from pregnancy |

## Enforcement rules

1. Mobile clients call `lifemate-api`; they do not query pregnancy/security/consent tables directly.
2. A protected handler resolves the authenticated caller Account server-side, resolves the canonical subject Person and calls the central pregnancy authorization resolver.
3. Client-provided role names, relationship labels, entitlement flags, grant status or consent state are never trusted.
4. `security.can_access_pregnancy_scope(...)` validates canonical episode ownership and current database state on every server authorization check.
5. Owner authorization requires an active `core.account_person_links` Self link.
6. Cross-person authorization requires an active episode-scoped grant, exact scope and active contextual pregnancy-sharing consent.
7. `pregnancy.owner.manage` is never cross-person authorized.
8. Relationship creation/change does not create pregnancy grants. Pregnancy activation does not create relationships, grants, consent or entitlements.
9. Revocation/expiry is effective on the next server request. A device may retain previously cached owner-approved content for its established offline contract, but stale cache is never evidence for a new remote authorization decision.
10. Pregnancy identifiers, health facts, consent state and scope membership must not be emitted as ordinary analytics/log payloads.

## Failure semantics

Authorization failures expose the stable client-safe code `pregnancy_access_denied` without revealing whether a supplied Person or episode UUID exists. More detailed API failure semantics are frozen in F0-04 (#780).
