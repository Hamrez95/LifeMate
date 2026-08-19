# ContactPoint envelope-key rotation runbook

Parent: Foundation security gate #217 / Identity-29 #369.

This runbook defines the source and operational contract for rotating the
external AES-GCM envelope key that protects canonical ContactPoint plaintext.
It does **not** authorize a live rotation while the repository/release control
plane in #210 is incomplete.

## Security invariants

- ContactPoint encryption keys and the dedicated contact hashing secret remain
  outside PostgreSQL, migrations, Git, workflow artifacts and database backups.
- PostgreSQL stores only the domain-separated contact HMAC, AES-GCM envelope,
  nonce and integer envelope-key version.
- `legacy` Profile contact lookup does not load active or previous envelope keys.
- Canonical `prefer-contact` / `contact-only` reads accept only the configured
  active or one configured previous envelope-key version.
- After raw Profile contact retirement, missing/unknown/corrupt envelope keys or
  envelopes fail closed with no plaintext/raw Profile fallback.
- Writers always encrypt new/updated ContactPoints with the active key. The
  previous key is decryption-only during the bounded rotation overlap.
- Re-encryption changes only ciphertext, nonce, envelope-key version and
  `updated_at_utc`; Account ownership, kind, normalized hash, status and
  `verified_at_utc` remain unchanged.
- ContactPoint key rotation never changes Account/AppUser/Person ownership,
  caregiver consent, access grants or healthcare authorization.

## Runtime configuration

The existing active writer contract remains authoritative:

- `LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY`
- `LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION`

A bounded overlap may additionally configure both of:

- `LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY`
- `LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION`

The previous pair is optional for runtime reads. Partial configuration, a weak
secret, malformed version or a previous version equal to the active version
fails closed before canonical ContactPoint access. Key versions are integers
from 1 through 32767.

## Safe rotation sequence

Do not skip or reorder these stages.

1. **Preconditions.** Confirm #210 control-plane protection is complete, exact
   `main` is the reviewed deployment source, the current contact encryption and
   hashing-key recovery owners are known, and #211/#226 recovery evidence keeps
   key material outside database backups.
2. **Generate the replacement envelope key outside PostgreSQL.** Use at least
   256 bits of unpredictable secret material and choose a new integer version
   different from the current version. Do not derive it from contact plaintext,
   the contact HMAC secret, or the previous envelope key.
3. **Install bounded overlap configuration.** Set the replacement key/version as
   the active pair and the formerly active key/version as the previous pair in
   protected runtime secrets. Keep the previous operational recovery copy until
   the rollback window closes.
4. **Deploy one reviewed exact-main build.** Existing previous-version envelopes
   remain readable through authenticated AES-GCM decryption. Every new Profile
   contact write is encrypted with the active key only.
5. **Run protected dry-run.** Dispatch `contact-point-key-rotation` from
   private/protected exact `main` through Environment `beta` with mode
   `dry-run`. Each previous-version envelope is decrypted, authenticated and
   checked against the externally keyed normalized contact HMAC. Dry-run never
   mutates PostgreSQL.
6. **Treat validation failures as incidents.** Unknown key versions, malformed
   envelopes, AES-GCM authentication failure or plaintext/HMAC mismatch block
   the batch. Do not skip the row, re-enable raw Profile contact storage, or
   rewrite contact ownership to make the batch pass.
7. **Apply bounded batches.** Re-run `contact-point-key-rotation` with mode
   `apply`, a batch size from 1 through 1000, the opaque ContactPoint UUID cursor
   from the prior batch when present, and exact confirmation
   `ROTATE-CONTACT-ENVELOPES`. One transaction owns each batch. Each update uses
   the complete previous envelope as an optimistic predicate so concurrent
   Profile writes/rotations fail closed instead of being overwritten.
8. **Repeat until no previous-version envelopes remain.** Apply is idempotent;
   already-active envelopes are validated/classified and not rewritten.
9. **Run protected readiness.** Dispatch
   `contact-point-key-rotation-readiness` only from private/protected exact
   `main` through Environment `beta`. It does not receive either encryption key
   or the hashing secret; output is version/count metadata only.
10. **Require GREEN evidence before previous-key removal.** There must be at
    least one current ContactPoint, every current ContactPoint must have a
    complete active-version envelope, and previous-version, unknown-version and
    invalid-envelope counts must all be zero.
11. **Remove previous runtime configuration.** Only after readiness is GREEN may
    the previous key/version pair be removed from deployed runtime configuration.
    Re-run contact-only Profile reads, self-service export, Profile update and
    patient/caregiver/unrelated authorization evidence after removal.
12. **Close the rollback window deliberately.** Retire the external previous-key
    recovery copy only under the approved key-custody process. No previous
    database envelope should remain once readiness was GREEN.

## Rollback / failure behavior

### Failure before previous-key removal

Keep both runtime keys available, correct the source/configuration issue and
redeploy the last reviewed exact-main state. Previous-version envelopes remain
readable and active-version writes remain authoritative.

### Concurrent mutation during apply

The optimistic update returns a privacy-safe conflict and rolls back the batch.
Re-run dry-run from a fresh cursor/snapshot. Do not force-update the envelope or
weaken the predicate.

### Active key lost while previous key remains

Do not promote the previous key silently or write new previous-version
envelopes. Recover the active key from the approved external operational backup,
or execute a separately reviewed forward rotation while preserving the
active/previous contract.

### Previous key lost before re-encryption completes

Previous-version ContactPoints become intentionally unavailable. Do not recover
by re-populating raw email/phone columns or bypassing contact-only. Restore the
previous key from the approved external recovery path and resume bounded
re-encryption.

### Both active and previous keys unavailable

Canonical ContactPoint reads and writes fail closed. Treat this as a
security/recovery incident under #211/#216. Do not reconstruct plaintext from
application logs, user exports or healthcare tables.

## Readiness evidence shape

The protected readiness audit may publish only:

- active envelope-key version;
- previous envelope-key version;
- number of current non-revoked ContactPoints;
- number with complete active-version envelopes;
- number with complete previous-version envelopes;
- number with unknown versions;
- number with invalid/incomplete envelope metadata;
- boolean `readyForPreviousKeyRemoval`.

It must not emit contact plaintext, normalized hashes, ciphertext, nonces,
database URLs, hashing/encryption secrets, provider credentials or healthcare
payloads. A zero-contact environment is not accepted as live GREEN evidence.

## Release rule

Source support for envelope-key rotation is necessary but not live evidence.
Until #210 is protected and a real protected dry-run/apply/readiness/recovery
exercise is performed, #217 remains open and database-breach/key-recovery claims
must not rely on untested ContactPoint rotation operations.
