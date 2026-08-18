# ContactPoint key rotation operator checklist

Companion checklist for `CONTACT_POINT_KEY_ROTATION.md`. This is a source-only
operator aid; it does not authorize live rotation while #210 remains open.

## Before overlap

- [ ] exact reviewed `main` is the deployment source and branch/environment protections are active;
- [ ] active ContactPoint encryption key/version and contact hashing secret recovery owners are confirmed outside PostgreSQL/backups;
- [ ] replacement encryption key is generated externally with a distinct version;
- [ ] previous-key recovery copy remains available for the rollback window;
- [ ] no raw Profile email/phone fallback is being re-enabled.

## During overlap

- [ ] new key/version is active and old key/version is configured only as the previous pair;
- [ ] contact-only Profile read and self-service export can read previous-version envelopes;
- [ ] new/updated ContactPoints are written with the active key only;
- [ ] protected `contact-point-key-rotation` dry-run validates each previous envelope cryptographically;
- [ ] any unknown version, AES-GCM authentication error, contact-HMAC mismatch or optimistic conflict is treated as a blocking incident;
- [ ] apply batches use at most 1000 current ContactPoints and exact confirmation `ROTATE-CONTACT-ENVELOPES`;
- [ ] each batch cursor/count summary contains no plaintext, hash, ciphertext, nonce, DB URL or key material.

## Before previous-key removal

- [ ] all apply batches are complete and idempotent rerun reports no previous-version mutation;
- [ ] protected `contact-point-key-rotation-readiness` is GREEN on a non-empty ContactPoint population;
- [ ] previous-version contacts = 0;
- [ ] unknown-version contacts = 0;
- [ ] invalid envelopes = 0;
- [ ] active-version ready contacts = current contacts;
- [ ] Profile read, Profile update and self-service export evidence is retained without sensitive payloads.

## After removal

- [ ] previous runtime key/version pair is removed only after GREEN readiness;
- [ ] contact-only Profile read/export/update are re-verified;
- [ ] patient/caregiver/unrelated authorization evidence remains unchanged;
- [ ] rollback/recovery evidence is captured under #211/#216 without storing key material in Git, issues or ordinary artifacts.
