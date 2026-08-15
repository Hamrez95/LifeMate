# LifeMate encrypted workstation backup

Parent evidence gate: #226. Source implementation: #227. Portability contract: #228.

## Boundary

The current production database happens to be hosted by Supabase, but this backup path is deliberately built on **standard PostgreSQL** client tools and libpq connection configuration. The operational scripts do not use the Supabase CLI, project refs, provider backup APIs or provider-owned database schemas.

Moving to another PostgreSQL provider must require only equivalent database roles/grants plus a new local connection service definition. The encrypted archive, retention, integrity and restore procedure stay the same.

The portable LifeMate data boundary is defined in `config/recovery/lifemate-postgres-backup.json`. Provider-owned schemas such as Auth, Storage, Realtime, Vault and provider migration metadata are intentionally excluded from this application-data archive. Canonical application migrations/source remain in Git and provider/runtime configuration is reconstructed separately.

## Security model

- `pg_dump` connects through a libpq service and immediately switches to the NOLOGIN `lifemate_backup_reader` role.
- That role is read-only and non-superuser. It has the narrow `BYPASSRLS` attribute because PostgreSQL requires a complete logical dump role to bypass RLS; otherwise `pg_dump` refuses or can only export policy-visible rows.
- The credential-bearing LOGIN is provisioned separately and only receives membership in `lifemate_backup_reader`. Its password is never committed.
- `pg_dump` custom-format bytes are streamed directly into `age`; the normal backup artifact on disk is ciphertext (`*.dump.age`).
- The private `age` identity never appears in PostgreSQL, Git, CI, a manifest or Task Scheduler arguments.
- `LIFEMATE_IDENTITY_LINK_KEY` remains outside PostgreSQL and outside the database backup. Recovery preserves only the database-side key reference/version needed by the identity-link design.
- Manifests contain ciphertext hashes and operational metadata only, not database host/user/password, auth subjects or health data.

The workstation itself therefore becomes sensitive operational infrastructure. Use full-disk encryption, a protected OS account and a separate offline copy of the `age` recovery identity.

## One-time workstation setup

### 1. Install prerequisites

Install PostgreSQL client tools compatible with the production major version, PowerShell 7, and `age`. Confirm these commands resolve from a new `pwsh` session:

```powershell
pg_dump --version
pg_restore --version
psql --version
age --version
age-keygen --version
```

### 2. Create the local recovery identity

Create a private directory outside the repository, restrict its ACL to the current Windows user, then generate a key:

```powershell
$keys = Join-Path $env:USERPROFILE '.lifemate\keys'
New-Item -ItemType Directory -Force $keys | Out-Null
& age-keygen -o (Join-Path $keys 'backup.agekey')
```

Record the **public recipient** (`age1...`) for the scheduled backup task. Do not copy the private identity into GitHub, Trello, a database table or a task argument. Keep a separate offline encrypted/recovery copy of the private identity; losing it makes encrypted backups unrecoverable.

### 3. Provision the database backup LOGIN

The repository migration creates the provider-neutral NOLOGIN role `lifemate_backup_reader`. An administrator must create a distinct LOGIN with no superuser/write/DDL/replication privileges and grant membership to the reader. Use a strong generated password; the example intentionally contains no password value:

```sql
CREATE ROLE lifemate_backup_operator
  LOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT lifemate_backup_reader TO lifemate_backup_operator;
```

The dump command uses `--role=lifemate_backup_reader`, so the session only elevates to the narrowly scoped read-only RLS-bypass role while exporting. Do not reuse the Edge, worker, migration or database-owner credential.

### 4. Configure libpq locally

Keep endpoint/user details in `pg_service.conf` and the password in `pgpass`, not in the scheduled command. You may use explicit user environment variables `PGSERVICEFILE` and `PGPASSFILE` to point libpq at founder-controlled files.

Example service file:

```ini
[lifemate-backup]
host=YOUR_POSTGRES_HOST
port=5432
dbname=postgres
user=lifemate_backup_operator
sslmode=require
```

Example `pgpass` record:

```text
YOUR_POSTGRES_HOST:5432:postgres:lifemate_backup_operator:YOUR_GENERATED_PASSWORD
```

Restrict both files to the founder OS account, especially the password file. When the database provider changes, update these local connection values; do not rewrite the backup scripts.

### 5. Test one encrypted backup manually

From a clean PowerShell 7 session with `PGSERVICEFILE`/`PGPASSFILE` available:

```powershell
$recipient = 'age1...PUBLIC_RECIPIENT...'
./tools/recovery/lifemate-local-backup.ps1 `
  -DatabaseService lifemate-backup `
  -AgeRecipient $recipient

./tools/recovery/check-lifemate-local-backup.ps1
```

A successful run creates only:

- `lifemate-<UTC>.dump.age` — encrypted PostgreSQL custom archive;
- `lifemate-<UTC>.manifest.json` — non-sensitive ciphertext/integrity metadata;
- `last-status.json` — redacted last-run status.

A `.part` file is removed on failure and never promoted to a valid backup.

## Daily Windows schedule

After a successful manual test, install the two current-user scheduled tasks:

```powershell
./tools/recovery/install-lifemate-backup-task.ps1 `
  -DatabaseService lifemate-backup `
  -AgeRecipient 'age1...PUBLIC_RECIPIENT...' `
  -DailyAt '03:00' `
  -RetentionDays 14
```

The backup task runs daily and uses `StartWhenAvailable`, so a missed 03:00 run can start when the workstation next becomes available. A second task checks freshness and ciphertext SHA-256 approximately three hours later. The task arguments contain the public recipient and service name but no database password or private recovery identity.

Treat a failed/stale freshness task or `last-status.json` with `state=failure` as an operational incident. #226 cannot be closed until a real workstation run is evidenced.

## Disposable restore exercise

Never test restore against production. Prepare an isolated PostgreSQL service whose name includes `restore`, `disposable` or `test`, provision the three restricted runtime roles from reviewed source with their non-superuser/NOBYPASSRLS attributes, and run:

```powershell
./tools/recovery/restore-lifemate-local-backup.ps1 `
  -EncryptedBackupPath 'C:\...\lifemate-YYYYMMDDTHHMMSSZ.dump.age' `
  -AgeIdentityPath "$env:USERPROFILE\.lifemate\keys\backup.agekey" `
  -TargetDatabaseService lifemate-disposable-restore `
  -Confirmation RESTORE-LIFEMATE-DISPOSABLE
```

The script verifies the ciphertext SHA-256 before decryption and streams plaintext directly from `age` into `pg_restore`; it does not persist a plaintext archive. It then verifies critical Account/Person/healthcare schemas/tables and ensures the Edge/worker/admin runtime roles are not superuser or BYPASSRLS.

The full #226 recovery exercise must additionally run the existing synthetic authorization journeys: patient/caregiver/unrelated access, post-revocation denial, retention/deletion invariants and identity-link key-reference recovery. Record measured restore duration and expected data-loss window against #211 (`RTO <= 4h`, `RPO <= 24h`).

## Provider migration checklist

When moving from the current provider to another PostgreSQL host:

1. provision PostgreSQL and apply canonical source/migrations;
2. recreate restricted runtime roles plus `lifemate_backup_reader`;
3. create a new local backup LOGIN and grant only reader membership;
4. update `pg_service.conf`/`pgpass` for the new host;
5. run one manual encrypted backup and freshness check;
6. restore that backup to an isolated target and run the same recovery/security checks;
7. only then retire the old provider-specific connection configuration.

No change to encrypted backup format, age key, retention policy or workstation scheduling is required solely because the PostgreSQL provider changed.
