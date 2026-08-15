# LifeMate account deletion — retention-v2

## Purpose

Account deletion is a destructive privacy workflow, not a simple `auth.users` delete. The closed-beta contract removes identity links and raw health data that belong to the deleting person while preserving only the minimum pseudonymous records required to keep shared-user data, consent/security evidence and relational integrity correct.

## Immediate request effects

When an authenticated user requests deletion:

- the identity account enters `DeletionPending`;
- the mapped LifeMate app user is disabled through `identity.accounts.legacy_app_user_id` — account IDs are **not** assumed to equal app-user IDs;
- external identities and app enrollments are disabled/suspended;
- active WellMate/CareMate relationships are revoked;
- ecosystem person relationships are ended;
- active access grants and entitlements are revoked;
- session-revocation and deletion-processing outbox messages are created idempotently.

The account can no longer continue normal healthcare access while deletion is waiting for worker processing.

## Worker cleanup before database finalization

The worker waits until the session-revocation event has completed, then:

1. soft-deletes the Supabase Auth subject using the service-role admin API;
2. lists and removes every server-owned profile-photo object under the mapped app-user folder in the `profile-photos` bucket;
3. calls the database finalizer only after Auth and Storage cleanup succeed.

Storage deletion uses the Storage API, not direct SQL. A transient Auth/Storage failure leaves the outbox item retryable and does **not** mark the database deletion request completed.

## Raw data that is hard-deleted

The finalizer deletes the deleting person's own:

- medications;
- treatment plans, schedules, dose occurrences and their cascading adherence events;
- care events where that person is the patient;
- health observations;
- women-calendar profile, episodes, daily logs and support actions where that person is the patient;
- derived daily adherence summaries;
- care invitations created by the deleting user, including contact/token hashes;
- idempotency rows for the deleted Auth subject because cached response bodies can contain healthcare data.

A care event or adherence event that belongs to **another patient** is not destroyed merely because the deleting user acted as caregiver/creator. Those shared records retain only the pseudonymous LifeMate app-user tombstone required for referential integrity.

## Identity and profile anonymization

After raw-data deletion:

- identity contact points and external identity rows are deleted;
- app-user `auth_subject` is replaced by a non-provider tombstone value and status becomes `Deleted`;
- user/person display name, email, phone, profile-photo path, birth date and home-region fields are removed or neutralized;
- person status becomes `Deleted` and subject category becomes `Unknown`;
- the identity account becomes `Deleted`;
- app enrollments become `Left`;
- audit records are retained only as minimal security evidence: the actor link is cleared and metadata is replaced by a deletion-redaction marker;
- account deletion request status becomes `Completed` with `retention-v2`.

## Deliberately retained pseudonymous records

The finalizer does not erase records that must preserve another person's data or minimal operational/compliance history, such as revoked shared relationships, consent/security records and permitted commercial/accounting evidence. They no longer have a direct contact/provider identity because contact points, external identities and the Auth subject link are removed.

This retention policy is a technical closed-beta contract. Country-specific statutory retention periods and production legal wording still require jurisdiction-specific legal review before a public healthcare launch.

## Security boundary

`identity.finalize_account_deletion(uuid)` is `SECURITY DEFINER` with a fixed `search_path`, accepts only a deletion-request UUID, validates request state, and is executable by `lifemate_worker_runtime` but not by the public/API runtime. Broad worker UPDATE/DELETE grants previously needed by the invoker function are revoked.

Automated integration tests use deliberately different identity-account and app-user UUIDs to prevent regressions that accidentally assume those identifiers are equal. They also prove that the deleting patient's raw healthcare data disappears while another patient's data created by that caregiver survives.
