# Offline-first local health store foundation

Issue: #829
Parent: #828

## Purpose

LifeMate needs one protected, structured local execution projection shared by WellMate, Women Health, CocoonMate and the future unified shell. The server remains canonical; the device keeps only the bounded state required for offline owner UX, local reminders and durable pending mutations.

This foundation deliberately does **not** create a second backend or mirror arbitrary Supabase tables.

## Storage boundary

`packages/lifemate_core` owns the reusable local-health persistence primitive.

Initial allowed projection classes are explicit:

- treatment plans and bounded treatment occurrences;
- care events/calendar items;
- Women Health cycle state required for offline use;
- active pregnancy snapshot and approved cached pregnancy content;
- canonical health observations required locally;
- pending local mutations;
- local notification schedule metadata.

Feature code cannot invent arbitrary domain strings. New local domains require a code review and enum addition.

## Privacy and encryption

The SQLite file is structured transactional storage, but LifeMate does not rely on SQLite file permissions alone.

- Every sensitive projection envelope is encrypted with AES-256-GCM.
- The random 256-bit master key is stored with `flutter_secure_storage` in the platform keystore/keychain boundary.
- Raw environment IDs, Account IDs, Person IDs, domain names and record keys are **not** stored in SQLite selectors.
- SQLite selectors are deterministic HMAC-SHA256 tokens derived using the protected master key.
- AES associated data binds ciphertext to its environment/account/person/domain/record selector tuple so row substitution/tampering fails authentication.
- The encrypted envelope contains payload plus source revision, sync cursor, content/rule version and local timestamp metadata.
- Health projection envelopes are bounded to 256 KiB plaintext to prevent this store from becoming an unrestricted file/document cache.

This is application-layer authenticated encryption; it is not a claim that the whole SQLite file uses SQLCipher. The remaining observable database information is limited to schema shape, opaque tokens and row counts.

## Key-loss behavior

If a database file already exists but its protected master key is unavailable or malformed, the store fails visibly with `LifeMateLocalStoreKeyUnavailableException`.

It must **not** generate a replacement key and silently make existing pending health actions unreadable. Recovery/product UX for an unrecoverable local key is handled explicitly by the host and later offline hardening work.

## Isolation and purge

Rows carry opaque keyed selectors for:

- environment;
- environment + Account;
- environment + Account + Person.

This permits:

- per-Account purge on sign-out/account switch without exposing raw IDs in the file;
- complete environment purge when changing staging/production/provider context;
- Person-level isolation for dependent/family contexts.

The local store must be initialized during normal app bootstrap before background isolates begin using local health execution infrastructure.

## Schema and migration safety

Schema version is stored in SQLite `PRAGMA user_version`.

- migrations run inside `BEGIN IMMEDIATE` / `COMMIT`;
- failed migration rolls back and does not advance `user_version`;
- a database newer than the client-supported version fails instead of being opened with unknown semantics;
- pending local data survives ordinary close/reopen and app-local database reuse.

No migration path may silently drop pending health mutations.

## Relationship to later offline tasks

#829 provides storage and isolation only.

- #830 owns deterministic local reminder/alarm scheduling.
- #831 owns the full durable mutation outbox, sync cursors, retry and domain-specific conflict reconciliation.
- #832/#833/#834 adapt WellMate, Women Health and CocoonMate respectively.
- #835 owns stale shared-access/revocation/auth-outage policy.
- #836 is the physical-device offline continuity gate.

The `pendingMutation` projection domain exists now so #831 can migrate the current secure-storage mutation queue into this structured foundation without introducing another local database.

## Verification

The package test suite covers:

- encrypt/decrypt round-trip;
- absence of raw Account/Person/domain/health payload text from persisted SQLite rows/file;
- environment/account/Person isolation;
- account/environment purge behavior;
- authenticated-encryption tamper failure;
- future-schema fail-closed behavior;
- transactional migration rollback marker behavior;
- close/reopen persistence for pending mutations;
- existing-database + missing-key fail-closed behavior;
- bounded payload enforcement.
