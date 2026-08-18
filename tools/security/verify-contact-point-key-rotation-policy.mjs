import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

function fail(message) {
  console.error(`ContactPoint key rotation policy failure: ${message}`);
  process.exit(1);
}

function requireMarkers(source, markers, context) {
  for (const marker of markers) {
    if (!source.includes(marker)) {
      fail(`${context} lost required marker: ${marker}`);
    }
  }
}

function forbidMarkers(source, markers, context) {
  for (const marker of markers) {
    if (source.includes(marker)) {
      fail(`${context} contains forbidden marker: ${marker}`);
    }
  }
}

const cryptoRuntime = read('supabase/functions/_shared/contact_point_crypto.ts');
const contactRuntime = read('supabase/functions/lifemate-api/contact_points.ts');
const rotatorRuntime = read(
  'supabase/functions/lifemate-api/contact_point_envelope_rotation.ts',
);
const rotationTool = read('tools/security/contact-point-key-rotation.ts');
const readinessTool = read(
  'tools/security/contact-point-key-rotation-readiness.ts',
);
const rotationWorkflow = read('.github/workflows/contact-point-key-rotation.yml');
const readinessWorkflow = read(
  '.github/workflows/contact-point-key-rotation-readiness.yml',
);
const runbook = read('docs/security/CONTACT_POINT_KEY_ROTATION.md');
const denoConfig = read('supabase/functions/lifemate-api/deno.json');

requireMarkers(
  cryptoRuntime,
  [
    'export type ContactEncryptionKeySet',
    'LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY',
    'LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION',
    'must be configured together',
    'Previous ContactPoint encryption key version must differ from the active key version.',
    'readContactEncryptionKeySet',
  ],
  'ContactPoint envelope-key configuration',
);

requireMarkers(
  contactRuntime,
  [
    'readContactEncryptionKeySet',
    'previousEncryptionKey',
    'rowKeyVersion === encryptionKeys.active.keyVersion',
    'rowKeyVersion === encryptionKeys.previous.keyVersion',
    'readContactEncryptionKeySet(readEnvironment).active',
    'contact_point_unavailable',
    'if (lookupMode === "legacy") return legacyValue;',
  ],
  'ContactPoint read/write rotation boundary',
);

requireMarkers(
  rotatorRuntime,
  [
    'decryptContactPoint',
    'hashContactPoint',
    'expectedHash !== row.normalizedValueHash',
    'encryptContactPoint',
    'status <> \'Revoked\'',
    'encryption_key_version=${row.keyVersion}',
    'encryption_nonce_b64=${row.nonceB64}',
    "encode(encrypted_value,'base64')=${row.ciphertextB64}",
    'contact_point_rotation_conflict',
  ],
  'ContactPoint envelope rotator',
);
forbidMarkers(
  rotatorRuntime.toLowerCase(),
  [
    "set status='pending'",
    "set status='verified'",
    'verified_at_utc=',
    'normalized_value_hash=',
    'account_id=',
  ],
  'ContactPoint envelope rotator mutation set',
);

requireMarkers(
  rotationTool,
  [
    'ROTATE-CONTACT-ENVELOPES',
    'value > 1000',
    'afterContactPointId',
    'createContactPointEnvelopeRotator',
    'rotator.validate',
    'rotator.rotate',
    'mode === "dry-run"',
    'console.log(JSON.stringify(summary))',
    'Plaintext, hashes, ciphertext',
  ],
  'bounded ContactPoint key rotation tool',
);
if (rotationTool.toLowerCase().includes('update identity.contact_points')) {
  fail('rotation tool must reuse the reviewed rotator instead of direct ContactPoint mutation.');
}

requireMarkers(
  readinessTool,
  [
    'readyForPreviousKeyRemoval',
    'activeVersionReadyContacts',
    'previousVersionContacts',
    'unknownVersionContacts',
    'invalidEnvelopeContacts',
    'currentContacts > 0',
    'console.log(JSON.stringify(result))',
    'key material are intentionally omitted',
  ],
  'ContactPoint key rotation readiness',
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
    fail(`rotation readiness must remain read-only: ${mutation.trim()}`);
  }
}
for (const secretName of [
  'LIFEMATE_CONTACT_HASHING_SECRET',
  'LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY"',
  'LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY"',
]) {
  if (readinessTool.includes(secretName)) {
    fail(`rotation readiness must not read secret key material: ${secretName}`);
  }
}

for (const [name, workflow] of [
  ['rotation workflow', rotationWorkflow],
  ['readiness workflow', readinessWorkflow],
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
      'verify-contact-point-key-rotation-policy.mjs',
    ],
    name,
  );
  forbidMarkers(
    workflow,
    ['\npull_request:', '\npush:', '\nschedule:', 'actions/upload-artifact', 'continue-on-error: true'],
    name,
  );
}

requireMarkers(
  rotationWorkflow,
  [
    'ROTATE-CONTACT-ENVELOPES',
    'LIFEMATE_CONTACT_KEY_ROTATION_MAX_CONTACTS',
    'test "$LIFEMATE_CONTACT_KEY_ROTATION_MAX_CONTACTS" -le 1000',
    'contact-point-key-rotation.ts',
    'plaintext contacts, hashes, ciphertext, nonces, DB URLs and key material are intentionally omitted',
    'contact-point-key-rotation-readiness',
  ],
  'rotation workflow',
);

requireMarkers(
  readinessWorkflow,
  [
    'contact-point-key-rotation-readiness.ts',
    'readyForPreviousKeyRemoval',
    'invalid envelopes',
    'key material are intentionally omitted',
  ],
  'rotation readiness workflow',
);
forbidMarkers(
  readinessWorkflow,
  [
    '${{ secrets.LIFEMATE_CONTACT_HASHING_SECRET }}',
    '${{ secrets.LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY }}',
    '${{ secrets.LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY }}',
  ],
  'rotation readiness workflow',
);

requireMarkers(
  runbook,
  [
    'LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY',
    'Do not skip or reorder these stages.',
    'ROTATE-CONTACT-ENVELOPES',
    'Require GREEN evidence before previous-key removal.',
    'Previous key lost before re-encryption completes',
    'Do not recover by re-populating raw email/phone columns',
    '#210',
    '#211',
  ],
  'ContactPoint key rotation runbook',
);

requireMarkers(
  denoConfig,
  ['contact_point_key_rotation_integration_test.ts'],
  'LifeMate API Deno tasks',
);

console.log(
  'ContactPoint envelope-key rotation remains bounded, externally keyed, fail-closed and readiness-gated.',
);
