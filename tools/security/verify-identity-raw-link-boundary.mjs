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

function requireMarkers(source, markers, context) {
  for (const marker of markers) {
    if (!source.includes(marker)) {
      fail(`${context} lost required marker: ${marker}`);
    }
  }
}

function forbidSqlOwnershipWrites(fileName, columnName) {
  const source = fs.readFileSync(path.join(apiRoot, fileName), 'utf8');
  const escapedColumn = columnName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const patterns = [
    new RegExp(
      `insert\\s+into\\s+lifemate\\.[a-z_]+\\s*\\([^)]*\\b${escapedColumn}\\b`,
      'is',
    ),
    new RegExp(
      `update\\s+lifemate\\.[a-z_]+[\\s\\S]{0,1200}?\\b${escapedColumn}\\s*=`,
      'i',
    ),
  ];
  for (const pattern of patterns) {
    if (pattern.test(source)) {
      fail(
        `${fileName} must not write legacy healthcare ownership column ${columnName}`,
      );
    }
  }
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
  'supabase/functions/lifemate-api/identity_bridge.ts',
  'supabase/functions/lifemate-api/identity_resolver.ts',
  'supabase/functions/lifemate-api/idempotency_legacy.ts',
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

const identityBridge = fs.readFileSync(
  path.join(apiRoot, 'identity_bridge.ts'),
  'utf8',
);
requireMarkers(
  identityBridge,
  [
    'rawIdentityRetirementEnabled',
    'LIFEMATE_IDENTITY_LINK_LOOKUP_MODE=token-only',
    'raw_identity_retirement_prerequisite_missing',
    'set auth_subject=null',
    'delete from identity.external_identities',
  ],
  'raw identity retirement bridge',
);
if (
  /insert\s+into\s+lifemate\.app_users\s*\([^)]*\bauth_subject\b/is.test(
    identityBridge,
  )
) {
  fail('identity retirement bridge must never insert a raw AppUser auth_subject.');
}
if (
  /update\s+lifemate\.app_users\s+set\s+(?:(?!\bwhere\b)[\s\S])*?\bauth_subject\s*=\s*(?!null\b)/i.test(
    identityBridge,
  )
) {
  fail('identity retirement bridge may only mutate AppUser auth_subject to NULL.');
}

const databaseFacade = fs.readFileSync(
  path.join(apiRoot, 'database.ts'),
  'utf8',
);
requireMarkers(
  databaseFacade,
  [
    'createIdentityResolver',
    'createLegacyLifeMateDatabase',
    'async function requireIdentity(',
    'identityResolver.requireIdentity(auth)',
    'privacyPreferences.requireRegistrationComplete(identity.appUserId)',
    'requireIdentity,',
  ],
  'database compatibility facade',
);
requireMarkers(
  databaseFacade,
  [
    'createMedication: personMedications.createMedication',
    'listMedications: personMedications.listMedications',
    'createTreatmentPlan: personTreatmentPlans.createTreatmentPlan',
    'listTreatmentPlans: personTreatmentPlans.listTreatmentPlans',
    'listDoseOccurrences: personDoseOccurrences.listDoseOccurrences',
    'reportDose: personDoseOccurrences.reportDose',
    'listCareDoseOccurrences: personDoseOccurrences.listCareDoseOccurrences',
  ],
  'Person-authoritative healthcare facade',
);

forbidSqlOwnershipWrites('person_medications.ts', 'owner_user_id');
forbidSqlOwnershipWrites('person_treatment_plans.ts', 'patient_user_id');
forbidSqlOwnershipWrites('person_dose_occurrences.ts', 'patient_user_id');

const indexSource = fs.readFileSync(path.join(apiRoot, 'index.ts'), 'utf8');
if (!indexSource.includes('from "./database.ts"')) {
  fail('production API must import the guarded database facade.');
}
if (indexSource.includes('database_legacy.ts')) {
  fail('production API must never import the legacy database implementation directly.');
}

const idempotencySource = fs.readFileSync(path.join(apiRoot, 'idempotency.ts'), 'utf8');
requireMarkers(
  idempotencySource,
  [
    'lifemate:idempotency-actor:v1:',
    'actor_subject_token',
    'findLegacyIdempotencyReplay',
  ],
  'idempotency runtime',
);
if (idempotencySource.includes('actor_auth_subject')) {
  fail('new idempotency runtime must not persist/query raw Auth subjects.');
}

const legacyIdempotency = fs.readFileSync(
  path.join(apiRoot, 'idempotency_legacy.ts'),
  'utf8',
);
if (!legacyIdempotency.includes('expires_at_utc > now()')) {
  fail('legacy idempotency bridge must be bounded to unexpired migration rows.');
}
for (const mutation of ['insert into ', 'update ', 'delete from ', 'truncate ']) {
  if (legacyIdempotency.toLowerCase().includes(mutation)) {
    fail(`legacy idempotency bridge must remain read-only: ${mutation.trim()}`);
  }
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
requireMarkers(
  readinessTool,
  [
    'readyForTokenOnly',
    'missingCanonicalTokens',
    'conflictingCanonicalTokens',
    'unmappedActiveAccounts',
    'deriveIdentityLinkToken',
  ],
  'retirement readiness tool',
);
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
  'Raw identity dependencies are frozen; protected retirement is null-only and destructive column/table drops remain blocked.',
);
