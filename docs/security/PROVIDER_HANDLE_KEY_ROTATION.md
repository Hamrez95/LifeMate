# Provider recovery-handle key rotation

Parent: Foundation security gate #217 / Identity-30 #373.

This runbook defines the source and operational contract for rotating the
external AES-GCM key that protects canonical Supabase Auth recovery handles.
It does **not** authorize a live rotation while #210 control-plane protection
and the required recovery evidence remain incomplete.

## Security invariants

- Provider-handle keys remain outside PostgreSQL, migrations, Git, workflow
  artifacts and database backups.
- PostgreSQL stores authenticated ciphertext, nonce, integer key version and
  opaque Account/provider metadata; it never stores the provider subject in the
  provider-handle table.
- Runtime writers always encrypt new/refreshed handles with the active key.
- During a bounded overlap, Worker recovery may decrypt only the configured
  active or one configured previous key version.
- Unknown versions, malformed envelopes, AES-GCM authentication failure or an
  invalid recovered Auth UUID fail closed.
- Once raw identity retirement is enabled, key rotation may never re-enable
  `app_users.auth_subject` fallback.
- Re-encryption changes only ciphertext, nonce, key version and
  `updated_at_utc`; Account, provider, issuer and status remain unchanged.
- Provider-handle rotation does not change Account/AppUser/Person mapping,
  consent, caregiver authorization or healthcare ownership.

## Runtime configuration

Existing active contract:

- `LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY`
- `LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION`

Optional bounded previous pair:

- `LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY`
- `LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION`

The previous pair must be configured together, use a different version from the
active key and is decryption-only. The API identity bridge continues to write
through the active contract only.

## Safe rotation sequence

1. Confirm #210 is complete and exact reviewed `main` is the only trusted
   operational source. Confirm the current provider-handle recovery-key owner
   and backup/recovery ownership under #211/#226.
2. Generate a new unpredictable envelope key outside PostgreSQL and choose a new
   integer version. Do not derive it from provider subjects or the previous key.
3. Configure the new pair as active and the former active pair as previous in
   protected runtime secrets. Keep the previous recovery copy through rollback.
4. Deploy one reviewed exact-main build. New/refreshed handles now use only the
   active key; existing previous-version handles remain recoverable by Worker.
5. Dispatch `provider-handle-key-rotation` from private/protected exact `main`
   through Environment `beta` in `dry-run` mode. Each previous-version handle is
   AES-GCM authenticated and the recovered value must be a valid UUID. Dry-run
   never mutates PostgreSQL.
6. Treat unknown versions, malformed ciphertext/nonces, authentication failure
   or invalid recovered subjects as incidents. Do not restore raw auth subjects
   or bypass raw-retirement controls.
7. Apply bounded batches of 1-1000 handles with confirmation
   `ROTATE-PROVIDER-HANDLES`. Use the opaque Account UUID cursor returned by the
   previous batch. Each batch is one transaction.
8. Each update must match the complete prior ciphertext/nonce/key-version tuple.
   A concurrent identity sync therefore causes a fail-closed conflict instead of
   overwriting a newer active-key handle.
9. Repeat until no previous-version active canonical handle remains.
10. Dispatch `provider-handle-key-rotation-readiness`. This workflow receives
    only DB URL + key **versions**, never either encryption key.
11. Require non-vacuous GREEN evidence: at least one current active canonical
    handle, every handle active-version ready, and zero previous/unknown/invalid
    envelope counts.
12. Only after GREEN may the previous runtime key/version be removed. Re-run
    provider-control/recovery and raw-retirement denial evidence after removal.
13. Retire the external previous-key recovery copy only through the approved key
    custody process after the rollback window closes.

## Failure / rollback behavior

- **Before previous-key removal:** keep both runtime keys, correct source/config
  and redeploy the last reviewed exact-main state.
- **Concurrent mutation:** the optimistic predicate fails the batch. Re-run a
  fresh dry-run; never force-update around the conflict.
- **Active key lost:** recover it through the approved external key-custody path;
  do not silently promote previous as a writer.
- **Previous key lost before migration completes:** previous-version handles are
  intentionally unavailable. Restore the previous key externally; do not
  repopulate raw provider subjects.
- **Both keys unavailable:** provider-control/recovery fails closed and is a
  security/recovery incident. Healthcare authorization must not be broadened.

## Readiness evidence shape

Only the following may be surfaced:

- active and previous key versions;
- current active canonical handle count;
- active-version ready count;
- previous-version count;
- unknown-version count;
- invalid-envelope metadata count;
- `readyForPreviousKeyRemoval`.

Never emit provider subjects, ciphertext, nonces, database URLs, encryption
keys, identity-link HMAC keys, contacts or healthcare payloads.

## Release rule

Source support is not live evidence. #217 remains open until protected live
configuration, bounded rotation/readiness and external key recovery are actually
exercised after #210, without placing key material in PostgreSQL/backups.
