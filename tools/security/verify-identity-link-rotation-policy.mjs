import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

function fail(message) {
  console.error(`Identity-link rotation policy failure: ${message}`);
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

const tokenRuntime = read(
  'supabase/functions/lifemate-api/identity_link_token.ts',
);
const resolverRuntime = read(
  'supabase/functions/lifemate-api/identity_resolver.ts',
);
const readinessTool = read(
  'tools/security/identity-link-key-rotation-readiness.ts',
);
const readinessWorkflow = read(
  '.github/workflows/identity-link-key-rotation-readiness.yml',
);
const runbook = read('docs/security/IDENTITY_LINK_KEY_ROTATION.md');
const denoConfig = read('supabase/functions/lifemate-api/deno.json');

requireMarkers(
  tokenRuntime,
  [
    'export type IdentityLinkKeySet',
    'LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY',
    'LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION',
    'must be configured together',
    'Previous identity-link key version must differ from the active key version.',
    'readIdentityLinkKeySetFromEnvironment',
  ],
  'identity-link key configuration',
);

requireMarkers(
  resolverRuntime,
  [
    'previousIdentityLinkKey',
    'readIdentityLinkKeySetFromEnvironment',
    'identity_token_rotation_conflict',
    'resolveTokenAppUserId',
    'upsertActiveToken',
    'activeRow.account_id !== previousRow.account_id',
    'if (lookupMode === "token-only")',
    'throw new ApiError(404, "not_onboarded", "Bootstrap is required.");',
  ],
  'identity resolver rotation boundary',
);

requireMarkers(
  readinessTool,
  [
    'readyForPreviousKeyRemoval',
    'currentVersionReadyAccounts',
    'missingActiveVersionTokens',
    'multipleActiveVersionTokens',
    'unmappedActiveAccounts',
    'LIFEMATE_IDENTITY_LINK_KEY_VERSION',
    'Subjects, token digests, DB URLs and key material are omitted.',
  ],
  'rotation readiness audit',
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
    fail(`rotation readiness audit must remain read-only: ${mutation.trim()}`);
  }
}
for (const secretMarker of [
  'LIFEMATE_IDENTITY_LINK_KEY"',
  'LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY',
]) {
  if (readinessTool.includes(secretMarker)) {
    fail(`rotation readiness audit must not read HMAC key material: ${secretMarker}`);
  }
}

requireMarkers(
  readinessWorkflow,
  [
    'workflow_dispatch:',
    'environment: beta',
    "test \"$GITHUB_REF\" = 'refs/heads/main'",
    'github.event.repository.private',
    'github.ref_protected',
    'git rev-parse HEAD',
    'persist-credentials: false',
    'verify-identity-raw-link-boundary.mjs',
    'verify-identity-link-rotation-policy.mjs',
    'identity-link-key-rotation-readiness.ts',
    'readyForPreviousKeyRemoval',
    'subjects, token digests, database URLs and key material are intentionally omitted',
  ],
  'protected rotation readiness workflow',
);
forbidMarkers(
  readinessWorkflow,
  [
    '\npull_request:',
    '\npush:',
    '\nschedule:',
    'actions/upload-artifact',
    'continue-on-error: true',
    '${{ secrets.LIFEMATE_IDENTITY_LINK_KEY }}',
    '${{ secrets.LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY }}',
  ],
  'protected rotation readiness workflow',
);

requireMarkers(
  runbook,
  [
    'LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY',
    'LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION',
    'Do not skip or reorder these stages.',
    'Require GREEN evidence before previous-key removal.',
    'Both active and previous keys unavailable',
    'do not re-enable raw-subject lookup',
    '#210',
    '#211',
  ],
  'identity-link key rotation runbook',
);

requireMarkers(
  denoConfig,
  ['identity_link_rotation_integration_test.ts'],
  'LifeMate API Deno tasks',
);

console.log(
  'Identity-link key rotation remains bounded, fail-closed, externally keyed and readiness-gated.',
);
