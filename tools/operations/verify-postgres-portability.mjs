import fs from 'node:fs';
import path from 'node:path';

const sqlRoots = [
  'supabase/bootstrap/legacy_lifemate_baseline.sql',
  'supabase/migrations',
];

function fail(message) {
  console.error(`PostgreSQL portability policy failure: ${message}`);
  process.exit(1);
}

function collectSqlFiles(entry) {
  const stat = fs.statSync(entry);
  if (stat.isFile()) return [entry];
  return fs.readdirSync(entry, { withFileTypes: true })
    .flatMap((item) => collectSqlFiles(path.join(entry, item.name)))
    .filter((file) => file.endsWith('.sql'));
}

// Remove comments and single-quoted SQL literals so opaque provider values such
// as 'supabase_auth' remain legal while schema/function dependencies stay visible.
// auth.uid()/auth.jwt() are bounded request-context adapter helpers; they do not
// make LifeMate own or query the provider's auth schema objects.
function executableSql(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--[^\n\r]*/g, ' ')
    .replace(/'(?:''|[^'])*'/g, "''")
    .replace(/\bauth\s*\.\s*(?:uid|jwt)\s*\(\s*\)/gi, 'NULL');
}

const sqlFiles = sqlRoots.flatMap(collectSqlFiles).sort();
if (sqlFiles.length < 2) fail('canonical baseline/migrations were not discovered');

const forbidden = [
  { pattern: /\bauth\s*\./i, label: 'provider-owned auth schema/object' },
  { pattern: /\bstorage\s*\./i, label: 'provider-owned storage schema' },
  { pattern: /\brealtime\s*\./i, label: 'provider-owned realtime schema' },
];

for (const file of sqlFiles) {
  const source = fs.readFileSync(file, 'utf8');
  const sql = executableSql(source);
  for (const { pattern, label } of forbidden) {
    if (pattern.test(sql)) fail(`${file} references ${label}`);
  }
}

const backup = fs.readFileSync('tools/recovery/lifemate-local-backup.ps1', 'utf8');
const restore = fs.readFileSync('tools/recovery/restore-lifemate-local-backup.ps1', 'utf8');
const backupRole = fs.readFileSync(
  'supabase/migrations/20260815210500_add_portable_backup_reader_role.sql',
  'utf8',
);
const compatibilityRoles = fs.readFileSync(
  'supabase/bootstrap/test_provider_compatibility_roles.sql',
  'utf8',
);
const architecture = fs.readFileSync('docs/architecture/POSTGRES_PORTABILITY.md', 'utf8');

if (!backup.includes('pg_dump')) fail('workstation backup must use standard pg_dump');
if (!restore.includes('pg_restore')) fail('workstation restore must use standard pg_restore');
for (const source of [backup, restore]) {
  if (/supabase\s+db\s+(dump|restore)/i.test(source)) {
    fail('operational backup/restore must not depend on Supabase CLI dump formats');
  }
}

for (const phrase of [
  'CREATE ROLE lifemate_backup_reader',
  'NOLOGIN',
  'NOSUPERUSER',
  'NOCREATEDB',
  'NOCREATEROLE',
  'NOREPLICATION',
  'BYPASSRLS',
  'REVOKE CREATE ON SCHEMA public FROM lifemate_backup_reader',
]) {
  if (!backupRole.includes(phrase)) {
    fail(`backup-reader migration is missing reviewed extraction constraint: ${phrase}`);
  }
}
if (/GRANT\s+(INSERT|UPDATE|DELETE|TRUNCATE|CREATE|ALL)\b[^;]*lifemate_backup_reader/i.test(backupRole)) {
  fail('backup reader must not receive mutation privileges');
}

for (const role of ['anon', 'authenticated', 'service_role']) {
  const createPattern = new RegExp(
    `create\\s+role\\s+${role}\\s+nologin\\s+nosuperuser\\s+nocreatedb\\s+nocreaterole\\s+noreplication\\s+nobypassrls`,
    'i',
  );
  if (!createPattern.test(compatibilityRoles)) {
    fail(`test provider compatibility role ${role} must be inert NOLOGIN/NOBYPASSRLS`);
  }
}
if (!compatibilityRoles.includes('TEST HARNESS ONLY')) {
  fail('provider compatibility roles must remain explicitly test-only');
}

for (const phrase of [
  'canonical LifeMate database is **LifeMate-owned PostgreSQL**',
  'auth.users',
  'storage.objects',
  'realtime.*',
  'opaque data values',
  'standard PostgreSQL connection strings',
  'pg_dump` / `pg_restore',
  'Backup-reader security exception',
  '`NOLOGIN`, read-only, `BYPASSRLS` role',
  'must never be generalized to Edge, worker or admin application runtimes',
  'provider-specific today',
  'does not prove that provider-specific Auth, Edge, Storage, Redis, WAF or DNS have already been abstracted',
]) {
  if (!architecture.includes(phrase)) fail(`portability document is missing: ${phrase}`);
}

console.log(`PostgreSQL portability source policy passed across ${sqlFiles.length} canonical SQL files with bounded auth context helpers and the reviewed narrow backup-reader RLS exception.`);
