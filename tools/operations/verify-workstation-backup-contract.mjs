import fs from 'node:fs';

const backup = fs.readFileSync('tools/recovery/lifemate-local-backup.ps1', 'utf8');
const restore = fs.readFileSync('tools/recovery/restore-lifemate-local-backup.ps1', 'utf8');
const installer = fs.readFileSync('tools/recovery/install-lifemate-backup-task.ps1', 'utf8');
const freshness = fs.readFileSync('tools/recovery/check-lifemate-local-backup.ps1', 'utf8');
const policy = JSON.parse(fs.readFileSync('config/recovery/lifemate-postgres-backup.json', 'utf8'));
const roleMigration = fs.readFileSync('supabase/migrations/20260815210500_add_portable_backup_reader_role.sql', 'utf8');
const runbook = fs.readFileSync('docs/operations/WORKSTATION_BACKUP.md', 'utf8');

function fail(message) {
  console.error(`Workstation backup contract failure: ${message}`);
  process.exit(1);
}
function requireText(source, value, message) {
  if (!source.includes(value)) fail(message);
}
function forbidText(source, value, message) {
  if (source.toLowerCase().includes(value.toLowerCase())) fail(message);
}

for (const [value, message] of [
  ['pg_dump', 'backup must use standard pg_dump'],
  ['--format=custom', 'backup must use a portable pg_dump archive'],
  ['--role=lifemate_backup_reader', 'pg_dump must switch to the narrow backup reader'],
  ['--dbname=service=', 'database location must come from libpq service configuration'],
  ['age_recipient', 'persisted backups must use age encryption'],
  ['.dump.age', 'persisted archive must be encrypted'],
  ['.part', 'backup must stage encrypted output before atomic publish'],
  ['Get-FileHash', 'backup must record ciphertext integrity'],
  ['last-status.json', 'backup must write redacted local status'],
]) requireText(backup, value, message);
forbidText(backup, 'supabase', 'operational backup script must not depend on Supabase');
forbidText(backup, 'project_ref', 'operational backup script must not depend on provider project refs');
forbidText(backup, 'password=', 'database password must not be embedded in backup source');

for (const [value, message] of [
  ['RESTORE-LIFEMATE-DISPOSABLE', 'restore must require explicit disposable-target confirmation'],
  ['Get-FileHash', 'restore must verify ciphertext before decryption'],
  ['age_recipient', 'restore must only accept the encrypted backup contract'],
  ['CopyToAsync', 'restore must stream plaintext instead of persisting a dump'],
  ['plaintextArchivePersisted = $false', 'restore evidence must state no plaintext archive was persisted'],
]) requireText(restore, value, message);
forbidText(restore, 'supabase', 'restore script must remain provider independent');

for (const [value, message] of [
  ['New-ScheduledTaskTrigger -Daily', 'Windows task must run daily'],
  ['StartWhenAvailable', 'missed workstation schedules must run when the machine becomes available'],
  ['check-lifemate-local-backup.ps1', 'scheduler must include a freshness check'],
  ['secretsInTaskArguments = $false', 'installer must make the no-secret-arguments boundary explicit'],
]) requireText(installer, value, message);
forbidText(installer, 'AgeIdentityPath', 'private recovery identity must never be placed in scheduled task arguments');
forbidText(installer, 'DatabasePassword', 'database password must never be a scheduled-task parameter');
requireText(freshness, 'MaximumAgeHours = 26', 'freshness check must enforce the closed-beta daily RPO guardrail');
requireText(freshness, 'Get-FileHash', 'freshness check must verify ciphertext integrity');

const requiredSchemas = [
  'analytics', 'care', 'commerce', 'consent', 'core', 'ecosystem',
  'identity', 'integration', 'lifemate', 'public', 'security',
];
for (const schema of requiredSchemas) {
  if (!policy.schemas.includes(schema)) fail(`LifeMate-owned schema missing from backup policy: ${schema}`);
}
for (const providerSchema of ['auth', 'storage', 'realtime', 'vault', 'supabase_migrations']) {
  if (policy.schemas.includes(providerSchema)) fail(`provider-owned schema must not be required for portable recovery: ${providerSchema}`);
}
if (policy.databaseEngine !== 'postgresql') fail('backup engine contract must remain PostgreSQL');
if (policy.defaultRetentionDays < 7) fail('local retention must preserve at least seven daily recovery points');

for (const [value, message] of [
  ['CREATE ROLE lifemate_backup_reader', 'backup reader must be provisioned by canonical SQL'],
  ['NOLOGIN', 'backup reader must not be directly loggable'],
  ['NOSUPERUSER', 'backup reader must never be superuser'],
  ['NOCREATEDB', 'backup reader must not create databases'],
  ['NOCREATEROLE', 'backup reader must not create roles'],
  ['NOREPLICATION', 'backup reader must not be a replication role'],
  ['BYPASSRLS', 'complete pg_dump requires an explicit narrow RLS bypass role'],
  ['GRANT SELECT ON ALL TABLES', 'backup reader must be read-only'],
]) requireText(roleMigration, value, message);
for (const mutation of ['GRANT INSERT', 'GRANT UPDATE', 'GRANT DELETE', 'GRANT TRUNCATE']) {
  forbidText(roleMigration, mutation, `backup reader must not receive mutation privilege: ${mutation}`);
}

for (const [value, message] of [
  ['standard PostgreSQL', 'runbook must state the provider-independent boundary'],
  ['pg_service.conf', 'runbook must keep host/user connection details outside the task command'],
  ['pgpass', 'runbook must keep the database password in libpq credential configuration'],
  ['LIFEMATE_IDENTITY_LINK_KEY', 'runbook must keep the identity-link protective key outside database backups'],
  ['#226', 'runbook must remain tied to the physical workstation evidence gate'],
]) requireText(runbook, value, message);

console.log('Workstation backup source is encrypted, daily, integrity-checked, least-privilege and PostgreSQL-provider independent.');
