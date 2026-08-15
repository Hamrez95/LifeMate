# LifeMate self-service data lifecycle contract

Status: **technical closed-beta contract**. This document describes what the current LifeMate runtime and product surfaces actually do. It is not a substitute for jurisdiction-specific legal/privacy review before a public healthcare launch.

## Why this document exists

The user-facing words for **Export my data** and **Delete account and personal data** must not promise behavior that the backend does not implement. The API, worker, database finalizer and WellMate/CareMate profile UI are therefore treated as one privacy lifecycle contract.

Canonical implementation references:

- `GET /api/v1/account/data-export`
- `POST /api/v1/account/deletion-requests`
- `supabase/functions/lifemate-api/data_export.ts`
- `supabase/functions/lifemate-api/account_lifecycle.ts`
- `supabase/functions/lifemate-worker/index.ts`
- `supabase/migrations/20260814215000_account_deletion_retention_v2.sql`
- `packages/lifemate_ui/lib/src/shared_profile_screen.dart`
- `packages/lifemate_client/lib/src/account_deletion_action.dart`
- `docs/privacy/ACCOUNT_DELETION_RETENTION.md`

## Export my data

The current profile action requests an **authenticated self-service portable JSON export**. It is a copy of the user's portable LifeMate data, not a database dump, security log export, provider credential export, or export of another person's raw identifiers.

### Runtime bounds

The current API contract is:

- schema: `lifemate-portable-export-v1`;
- maximum 20,000 rows per bounded dataset;
- maximum serialized response size: 8 MiB;
- sequential database reads so one export cannot fan out into multiple database connections;
- `Cache-Control: no-store` on API JSON responses;
- the mobile UI warns that the resulting JSON contains personal/health information and that copying it places the complete returned JSON on the device clipboard.

If one bounded dataset or the final response exceeds the self-service limit, the API returns `413 data_export_too_large` rather than silently truncating the export.

### Included self-owned/portable domains

Subject to the current schema and bounds, the export contains the user's portable representation of:

- LifeMate account status and profile;
- identity account metadata, verified/contact-point state without raw encrypted contact values, external provider type/state without raw provider subject, and app enrollment state;
- account-deletion request history;
- medications;
- treatment plans and schedules;
- dose occurrences and adherence events for the user as patient;
- care events for the user as patient;
- health observations owned by the user;
- privacy consents;
- care relationships with the user's role/scopes while omitting the other person's raw user identifier;
- care invitations created by the user without token/contact hashes;
- women-calendar profile, episodes and daily logs owned by the user;
- women-calendar support actions received by the user without exposing the caregiver's raw identifier.

### Deliberate export exclusions

The portable export intentionally does **not** include:

- raw authentication/provider subjects;
- encrypted contact values or contact hashes;
- invitation token/contact hashes;
- raw identifiers belonging to linked people;
- internal audit/security logs;
- idempotency keys/cached response records;
- outbox transport records.

Those exclusions are privacy/security boundaries, not missing rows that the product may silently claim to export.

## Delete account and personal data

The deletion flow is asynchronous and destructive. It is not represented as an immediate physical erase of every row in every system.

### Immediately after a valid request

The runtime contract immediately moves the identity account into deletion-pending state, disables the mapped legacy LifeMate app user, revokes/suspends active access paths and relationships, and queues session-revocation/deletion work. Account UUID, AppUser UUID and Person UUID are resolved through the identity bridge and are never assumed to be equal.

The client signs out after the deletion request is accepted. Worker completion is tracked separately.

### Worker and finalizer behavior

Before database finalization, the worker waits for session revocation, removes the Supabase Auth subject through the provider admin API, and deletes server-owned profile-photo objects. A transient Auth/Storage failure remains retryable and does not falsely mark the deletion request completed.

The retention-v2 database finalizer then removes raw healthcare/women-calendar data owned by the deleting person, private invitation/idempotency material and direct identity/contact/provider links, and neutralizes the remaining identity/profile tombstone.

### Records that may deliberately remain

LifeMate may retain the minimum pseudonymous records needed to preserve:

- another person's shared healthcare data that the deleting user merely acted on as caregiver/creator;
- revoked relationship/consent/security evidence;
- referential integrity and minimal operational history;
- permitted commercial/accounting evidence where applicable.

The retained records must no longer provide the direct contact/provider identity links removed by retention-v2.

The product deletion confirmation therefore says that owned health/women-calendar data, sign-in identifiers and profile files are removed/anonymized while minimum pseudonymous records needed for security, consent, shared-data integrity or legal retention may remain. This wording matches the current technical behavior; it does not define a statutory retention period.

## What this technical gate does not approve

This contract does **not** decide:

- country-specific statutory retention periods;
- final public Privacy Notice or Terms wording;
- legal basis for research/commercial processing;
- regulator/healthcare-provider obligations;
- support-process identity verification for exceptional privacy requests.

Those remain explicit human/legal launch gates. Engineering must not mark them passed because this source contract is green.

## Change-control rule

A change to export scope/bounds/exclusions, deletion timing, hard-delete domains, pseudonymous retention or user-facing export/deletion wording must update this document and the automated privacy lifecycle contract test in the same pull request. The test intentionally fails when the reviewed runtime/user wording drifts from this contract.
