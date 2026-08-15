import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const apiRoot = path.join(repoRoot, 'supabase/functions/lifemate-api');
const migrationRoot = path.join(repoRoot, 'supabase/migrations');

function fail(message) {
  console.error(`Identity raw-link boundary failure: ${message}`);
  process.exit(1);
}

function filesUnder(root, predicate) {
  const output = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const absolute = path.join(root, entry.name);
    if (entry.isDirectory()) output.push(...filesUnder(absolute, predicate));
    else if (predicate(absolute)) output.push(absolute);
  }
  return output;
}

const runtimeFiles = filesUnder(
  apiRoot,
  (file) => file.endsWith('.ts') &&
    !file.endsWith('_test.ts') &&
    !file.endsWith('_integration_test.ts'),
);
const relative = (file) => path.relative(repoRoot, file).replaceAll('\\', '/');

const authSubjectAllowlist = new Set([
  'supabase/functions/lifemate-api/database_legacy.ts',
  'supabase/functions/lifemate-api/identity_resolver.ts',
]);
const providerSubjectAllowlist = new Set([
  'supabase/functions/lifemate-api/identity_bridge.ts',
]);

for (const file of runtimeFiles) {
  const name = relative(file);
  const source = fs.readFileSync(file, 'utf8');
  if (source.includes('auth_subject') && !authSubjectAllowlist.has(name)) {
    fail(`production runtime file has an unapproved raw auth_subject dependency: ${name}`);
  }
  if (source.includes('provider_subject') && !providerSubjectAllowlist.has(name)) {
    fail(`production runtime file has an unapproved raw provider_subject dependency: ${name}`);
  }
  if (name !== 'supabase/functions/lifemate-api/database.ts' && source.includes('database_legacy.ts')) {
    fail(`legacy database implementation may only be imported by the compatibility facade: ${name}`);
  }
}

const databaseFacade = fs.readFileSync(
  path.join(apiRoot, 'database.ts'),
  'utf8',
);
for (const marker of [
  'createIdentityResolver',
  'createLegacyLifeMateDatabase',
  'requireIdentity: identityResolver.requireIdentity',
]) {
  if (!databaseFacade.includes(marker)) {
    fail(`database compatibility facade lost required token resolver marker: ${marker}`);
  }
}

const indexSource = fs.readFileSync(path.join(apiRoot, 'index.ts'), 'utf8');
if (!indexSource.includes('from "./database.ts"')) {
  fail('production API must import the guarded database facade.');
}
if (indexSource.includes('database_legacy.ts')) {
  fail('production API must never import the legacy database implementation directly.');
}

const migrations = filesUnder(migrationRoot, (file) => file.endsWith('.sql'));
const destructiveRawLinkPatterns = [
  /drop\s+column(?:\s+if\s+exists)?\s+auth_subject\b/i,
  /drop\s+column(?:\s+if\s+exists)?\s+provider_subject\b/i,
  /drop\s+table(?:\s+if\s+exists)?\s+identity\.external_identities\b/i,
];
for (const file of migrations) {
  const source = fs.readFileSync(file, 'utf8');
  for (const pattern of destructiveRawLinkPatterns) {
    if (pattern.test(source)) {
      fail(
        `destructive raw identity retirement is forbidden before explicit post-token-only evidence: ${relative(file)}`,
      );
    }
  }
}

const readinessTool = fs.readFileSync(
  path.join(repoRoot, 'tools/security/identity-link-retirement-readiness.ts'),
  'utf8',
);
for (const marker of [
  'readyForTokenOnly',
  'missingCanonicalTokens',
  'conflictingCanonicalTokens',
  'unmappedActiveAccounts',
  'deriveIdentityLinkToken',
]) {
  if (!readinessTool.includes(marker)) {
    fail(`retirement readiness tool lost required fail-closed marker: ${marker}`);
  }
}
for (const mutation of [
  'insert into ',
  'update identity.',
  'update lifemate.',
  'delete from ',
  'alter table ',
  'drop table ',
  'truncate ',
]) {
  if (readinessTool.toLowerCase().includes(mutation)) {
    fail(`retirement readiness audit must remain read-only: ${mutation.trim()}`);
  }
}

console.log(
  'Raw identity runtime dependencies are frozen to migration compatibility modules; destructive retirement remains blocked.',
);
