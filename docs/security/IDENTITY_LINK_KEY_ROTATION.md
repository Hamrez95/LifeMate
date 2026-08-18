# Identity-link key rotation runbook

Parent: Foundation security gate #217 / Identity-28 #367.

This runbook defines the source and operational contract for rotating the
external HMAC key that protects LifeMate authentication-subject lookup tokens.
It does **not** authorize a live rotation while the repository/release control
plane in #210 is incomplete.

## Security invariants

- The active and previous HMAC secrets live only in protected runtime/provider
  secret storage and an independently protected operational recovery path.
- Neither secret may be stored in PostgreSQL, Supabase Vault tables, migrations,
  Git, workflow logs, issue comments, database backups or ordinary artifacts.
- PostgreSQL stores only opaque token digests plus their integer key version.
- `legacy` identity lookup never loads the active or previous key.
- `token-only` never falls back to raw Auth/provider subjects when a token is
  missing, unreadable, conflicting or the external key is unavailable.
- Account/AppUser/Person authorization mapping and caregiver consent/access
  grants remain unchanged by key rotation.
- A rotation overlap supports exactly one active key and at most one previous
  key. More than one historical runtime key is intentionally unsupported.

## Runtime configuration

The existing active-key contract remains authoritative:

- `LIFEMATE_IDENTITY_LINK_KEY`
- `LIFEMATE_IDENTITY_LINK_KEY_VERSION`

A bounded rolling overlap may additionally configure both of:

- `LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY`
- `LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION`

The previous pair is optional. Partial configuration, a weak secret, malformed
version or a previous version equal to the active version fails closed before
database access. Key versions are integers from 1 through 65535.

The Command Center API consumes the same active/previous identity contract so a
Core key rotation does not strand administrator Account resolution during the
overlap. Its resolver is read-only with respect to identity tokens: Core runtime
traffic or the separately reviewed token backfill path performs convergence to
the active version, and the shared readiness gate prevents previous-key removal
until that convergence is complete.

## Safe rotation sequence

Do not skip or reorder these stages.

1. **Preconditions.** Confirm #210 control-plane protection is complete, exact
   `main` is the reviewed deployment source, the current key recovery owner is
   known, and #211/#226 recovery evidence keeps key material outside database
   backups.
2. **Generate the replacement key outside PostgreSQL.** Use at least 256 bits of
   unpredictable secret material and choose a new key version different from the
   current version. Never derive the new key from the old key or a user value.
3. **Install overlap configuration in protected runtime secrets.** Set the new
   key/version as the active pair and the formerly active key/version as the
   previous pair. Do not delete the old operational recovery copy yet.
4. **Deploy one reviewed exact-main build.** During overlap, token lookup derives
   both candidates. If the active token resolves, no migration write is needed.
   If only the previous token resolves, the resolver validates that
   Account/AppUser mapping and atomically upserts the active-version token for
   the same Account. The previous token remains intact for rolling-deploy
   compatibility. Command Center accepts either consistent candidate but does
   not mutate the shared token table.
5. **Treat any cross-key mismatch as an incident.** If active and previous
   candidates resolve to different Accounts, or either candidate has an
   ambiguous/broken Account mapping, authentication fails closed with a
   privacy-safe conflict. Do not repair this by enabling raw-ID fallback or
   manually relinking healthcare rows.
6. **Drive convergence.** Normal authenticated Core traffic lazily migrates
   active Accounts. If some Accounts do not naturally authenticate during the
   window, use a separately reviewed protected token backfill path rather than
   extending raw identity storage.
7. **Run the protected rotation-readiness audit.** Dispatch
   `identity-link-key-rotation-readiness` only from private/protected exact
   `main` through Environment `beta`. It reads only the database URL and active
   key version; it does not need either HMAC secret. The output is counts only.
8. **Require GREEN evidence before previous-key removal.** Every Active Account
   mapped to an Active AppUser must have exactly one Active canonical
   `supabase_auth/supabase` token at the active version; no mapped Active Account
   may be missing that token, no Account may have multiple active-version
   canonical tokens, and there must be no unmapped Active Account.
9. **Remove previous runtime configuration.** Only after the readiness gate is
   GREEN may the previous pair be removed from Core and Command Center runtime
   configuration. Re-run token-only authentication, Command Center Account
   resolution and patient/caregiver/unrelated authorization evidence after the
   change.
10. **Retire old database token rows separately.** This runbook does not delete
    historical token rows. Destructive old-version cleanup requires a separate
    reviewed, bounded and reversible/evidence-gated operation after the rollback
    window closes.

## Rollback / failure behavior

### Failure before previous-key removal

Keep both key pairs available in protected secret storage. Correct the source or
configuration issue and redeploy the last reviewed exact-main state. Do not
change Account/Person ownership to make a token lookup pass.

### Failure after previous-key removal

If the previous key is still inside the approved operational recovery window,
restore it only as the previous pair and redeploy the same reviewed source. Run
rotation readiness again before attempting removal a second time.

### Active key lost while previous key remains

The deployment must not silently promote an unreviewed key or fall back to raw
Auth identifiers. Recover the active key from the approved external operational
backup, or perform a separately reviewed rotation using the still-controlled
previous key and protected source path.

### Both active and previous keys unavailable

Authentication through protected identity tokens fails closed. Do not create new
Accounts for known identities, do not re-enable raw-subject lookup as an
emergency shortcut, and do not rewrite healthcare ownership. Treat this as a
security/recovery incident under #211/#216.

## Readiness evidence shape

The protected audit may publish only:

- active key version;
- number of Active Accounts;
- number of Accounts with exactly one active-version canonical token;
- number missing an active-version canonical token;
- number with multiple active-version canonical tokens;
- number of unmapped Active Accounts;
- boolean `readyForPreviousKeyRemoval`.

It must not emit raw Auth/provider subjects, HMAC token digests, database URLs,
HMAC secrets, provider credentials, email/phone values or healthcare payloads.

## Release rule

Source support for rotation is necessary but not live evidence. Until #210 is
protected and a real rotation/readiness exercise is performed through the
protected Environment, #217 remains open and no database-breach unlinkability
claim may rely on untested key-rotation recovery.
