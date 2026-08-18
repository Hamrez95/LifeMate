import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

function fail(message) {
  console.error(`ContactPoint migration policy failure: ${message}`);
  process.exit(1);
}

function requireMarkers(source, markers, context) {
  for (const marker of markers) {
    if (!source.includes(marker)) fail(`${context} lost required marker: ${marker}`);
  }
}

function forbidMarkers(source, markers, context) {
  for (const marker of markers) {
    if (source.includes(marker)) fail(`${context} contains forbidden marker: ${marker}`);
  }
}

const readinessWorkflow = read('.github/workflows/contact-point-readiness.yml');
const backfillWorkflow = read('.github/workflows/contact-point-backfill.yml');
const readinessTool = read('tools/security/contact-point-readiness.ts');
const backfillTool = read('tools/security/contact-point-backfill.ts');
const contactRuntime = read('supabase/functions/lifemate-api/contact_points.ts');
const profileRuntime = read('supabase/functions/lifemate-api/profile.ts');
const databaseRuntime = read('supabase/functions/lifemate-api/database.ts');
const bootstrapRuntime = read(
  'supabase/functions/lifemate-api/raw_contact_retirement_bootstrap.ts',
);
const dataExportRuntime = read('supabase/functions/lifemate-api/data_export.ts');
const denoConfig = read('supabase/functions/lifemate-api/deno.json');

for (const [name, workflow] of [
  ['readiness workflow', readinessWorkflow],
  ['backfill workflow', backfillWorkflow],
]) {
  requireMarkers(
    workflow,
    [
      'workflow_dispatch:',
      'environment: beta',
      "test \"$GITHUB_REF\" = 'refs/heads/main'",
      'github.event.repository.private',
      'github.ref_protected',
      'git rev-parse HEAD',
      'persist-credentials: false',
      'LIFEMATE_CONTACT_HASHING_SECRET',
      'LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY',
      'LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION',
    ],
    name,
  );
  forbidMarkers(
    workflow,
    ['\npull_request:', '\npush:', 'actions/upload-artifact', 'continue-on-error: true'],
    name,
  );
}

requireMarkers(
  readinessWorkflow,
  [
    'tools/security/contact-point-readiness.ts',
    'readyForContactOnly',
    'plaintext contacts, hashes, ciphertext, DB URLs and key material are intentionally omitted',
  ],
  'readiness workflow',
);
requireMarkers(
  backfillWorkflow,
  [
    "BACKFILL-ENCRYPTED-CONTACTS",
    'LIFEMATE_CONTACT_BACKFILL_MAX_ACCOUNTS',
    "test \"$LIFEMATE_CONTACT_BACKFILL_MAX_ACCOUNTS\" -le 1000",
    'tools/security/contact-point-backfill.ts',
    'run contact-point-readiness after the final apply batch',
  ],
  'backfill workflow',
);

requireMarkers(
  readinessTool,
  [
    'readyForContactOnly',
    'missingCanonical',
    'mismatchedCanonical',
    'conflictingOwner',
    'invalidEnvelope',
    'unmappedActiveAccounts',
    'decryptContactPoint',
    'console.log(JSON.stringify(result))',
  ],
  'readiness tool',
);
for (const mutation of [
  'insert into identity.contact_points',
  'update identity.contact_points',
  'delete from identity.contact_points',
  'truncate identity.contact_points',
  'alter table identity.contact_points',
]) {
  if (readinessTool.toLowerCase().includes(mutation)) {
    fail(`readiness tool must remain read-only: ${mutation}`);
  }
}

requireMarkers(
  backfillTool,
  [
    'createContactPointWriter',
    'maxAccounts',
    'value > 1000',
    'afterAccountId',
    'dry-run',
    'apply',
    'BACKFILL-ENCRYPTED-CONTACTS',
    'ContactPoint backfill conflicts with a contact owned by another Account.',
    'console.log(JSON.stringify(summary))',
  ],
  'backfill tool',
);
for (const directMutation of [
  'insert into identity.contact_points',
  'update identity.contact_points',
  'delete from identity.contact_points',
  'truncate identity.contact_points',
]) {
  if (backfillTool.toLowerCase().includes(directMutation)) {
    fail(`backfill tool must reuse the production writer instead of direct mutation: ${directMutation}`);
  }
}

requireMarkers(
  contactRuntime,
  [
    'export type ContactPointLookupMode =',
    '| "legacy"',
    '| "prefer-contact"',
    '| "contact-only"',
    'LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE',
    'LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED',
    'LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT',
    'LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE',
    'Raw Profile contact retirement requires LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE=contact-only.',
    'Raw Profile contact retirement requires LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE=true.',
    'contact-only Profile reads require LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED=true',
    'contact-only Profile reads require LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE=true',
    'contact_point_unavailable',
    'if (lookupMode === "legacy") return legacyValue;',
  ],
  'ContactPoint runtime',
);
requireMarkers(
  profileRuntime,
  [
    'createContactPointReader',
    'createContactPointWriter',
    'const rawPhone = contactReader.rawRetirementEnabled',
    'const rawEmail = contactReader.rawRetirementEnabled ? null : auth.email;',
    'compatibilityRows[0].phone_number = await contactReader.readForProfile',
    'compatibilityRows[0].email = await contactReader.readForProfile',
  ],
  'Profile runtime',
);
requireMarkers(
  databaseRuntime,
  [
    'rawContactRetirementEnabled',
    'createRawContactRetirementBootstrapStore',
    'if (rawContactRetirement)',
    'retirementBootstrap.bootstrapUser',
  ],
  'database facade',
);
requireMarkers(
  bootstrapRuntime,
  [
    'createContactPointWriter',
    'phone_number = null',
    'email = null',
    'null, null',
    'contactPoints.syncForLegacyAppUser',
    '"if-missing"',
    "'user.bootstrap'",
  ],
  'raw-contact retirement bootstrap',
);
requireMarkers(
  dataExportRuntime,
  [
    'createContactPointReader',
    'contactReader.readForProfile',
    'encrypted contact values and contact hashes',
  ],
  'self-service data export',
);
requireMarkers(
  denoConfig,
  [
    'contact_point_read_mode_test.ts',
    'contact_point_read_mode_integration_test.ts',
    'contact_point_data_export_integration_test.ts',
    'raw_contact_retirement_integration_test.ts',
  ],
  'LifeMate API Deno tasks',
);

console.log(
  'ContactPoint readiness, bounded backfill, read cutover and raw write retirement remain protected, fail-closed and CI-enforced.',
);
