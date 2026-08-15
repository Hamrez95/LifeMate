import fs from 'node:fs';

const workflowPath = '.github/workflows/main-final-android-release.yml';
const workflow = fs.readFileSync(workflowPath, 'utf8');

function fail(message) {
  console.error(`Stable workflow policy failure: ${message}`);
  process.exit(1);
}

function extractJob(source, jobName) {
  const lines = source.split('\n');
  const start = lines.findIndex((line) => line === `  ${jobName}:`);
  if (start === -1) {
    fail(`missing ${jobName} job`);
  }

  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^  [A-Za-z0-9_-]+:\s*$/.test(lines[index])) {
      end = index;
      break;
    }
  }

  return lines.slice(start, end).join('\n');
}

function extractNamedStep(job, stepName) {
  const lines = job.split('\n');
  const start = lines.findIndex((line) => line === `      - name: ${stepName}`);
  if (start === -1) {
    fail(`missing ${stepName} step in verify-and-build`);
  }

  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^      - (?:name:|uses:)/.test(lines[index])) {
      end = index;
      break;
    }
  }

  return lines.slice(start, end).join('\n');
}

function requireScopedText(block, value, message) {
  if (!block.includes(value)) {
    fail(message);
  }
}

const releaseJob = extractJob(workflow, 'verify-and-build');

requireScopedText(
  releaseJob,
  "    if: ${{ github.event_name == 'workflow_dispatch' }}",
  'verify-and-build must remain manual-only',
);
requireScopedText(
  releaseJob,
  '    environment: beta',
  'verify-and-build must remain bound to the beta Environment',
);
requireScopedText(
  releaseJob,
  '      SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}',
  'verify-and-build must receive the Supabase deployment credential',
);
requireScopedText(
  releaseJob,
  '      TELEMETRY_SMOKE_EMAIL: ${{ secrets.BETA_PATIENT_EMAIL }}',
  'verify-and-build must require the beta patient smoke email',
);
requireScopedText(
  releaseJob,
  '      TELEMETRY_SMOKE_PASSWORD: ${{ secrets.BETA_PATIENT_PASSWORD }}',
  'verify-and-build must require the beta patient smoke password',
);
for (const [name, secret] of [
  ['ROLE_PATIENT_EMAIL', 'BETA_PATIENT_EMAIL'],
  ['ROLE_PATIENT_PASSWORD', 'BETA_PATIENT_PASSWORD'],
  ['ROLE_CAREGIVER_EMAIL', 'BETA_CAREGIVER_EMAIL'],
  ['ROLE_CAREGIVER_PASSWORD', 'BETA_CAREGIVER_PASSWORD'],
  ['ROLE_UNRELATED_EMAIL', 'BETA_UNRELATED_EMAIL'],
  ['ROLE_UNRELATED_PASSWORD', 'BETA_UNRELATED_PASSWORD'],
]) {
  requireScopedText(
    releaseJob,
    '      ' + name + ': ${{ secrets.' + secret + ' }}',
    `verify-and-build must receive ${secret} for the final live role smoke`,
  );
}

if (releaseJob.includes("github.event_name == 'push'")) {
  fail('verify-and-build must never run from a push event');
}

const foundationStep = extractNamedStep(
  releaseJob,
  'Require main source and explicit foundation closure',
);
requireScopedText(
  foundationStep,
  "          test \"$CONFIRM_FOUNDATION_RELEASE\" = 'RELEASE-FOUNDATION-CLOSED'",
  'manual stable build must require explicit foundation closure confirmation in its release step',
);

const edgeVerificationStep = extractNamedStep(
  releaseJob,
  'Verify Edge API telemetry readiness and workers',
);
requireScopedText(
  edgeVerificationStep,
  '(cd supabase/functions/lifemate-worker && deno fmt --check && deno task check && deno task test)',
  'stable release must run the worker policy tests before deployment',
);

const credentialStep = extractNamedStep(
  releaseJob,
  'Require exact-main deployment credentials',
);
requireScopedText(
  credentialStep,
  '          if [ -z "$SUPABASE_ACCESS_TOKEN" ]; then',
  'stable build must fail closed when the exact-main deployment credential is absent',
);
requireScopedText(
  credentialStep,
  '          if [ -z "$TELEMETRY_SMOKE_EMAIL" ] || [ -z "$TELEMETRY_SMOKE_PASSWORD" ]; then',
  'stable build must fail closed when the authenticated beta smoke identity is absent',
);
requireScopedText(
  credentialStep,
  '            ROLE_CAREGIVER_EMAIL ROLE_CAREGIVER_PASSWORD \\',
  'stable build must fail closed when caregiver role credentials are absent',
);
requireScopedText(
  credentialStep,
  '            ROLE_UNRELATED_EMAIL ROLE_UNRELATED_PASSWORD; do',
  'stable build must fail closed when unrelated role credentials are absent',
);

const deploymentStep = extractNamedStep(releaseJob, 'Deploy exact main Edge source');
requireScopedText(
  deploymentStep,
  '          supabase functions deploy lifemate-worker \\\n            --project-ref "$SUPABASE_PROJECT_REF" \\\n            --no-verify-jwt \\\n            --use-api',
  'stable release must deploy the exact-main worker with its custom-auth boundary',
);

const readinessStep = extractNamedStep(
  releaseJob,
  'Require restricted readiness role on transaction pooler',
);
requireScopedText(
  readinessStep,
  '.databaseTransport == "transaction_pooler" and .transactionPoolerRequired == true',
  'stable build must keep the transaction-pooler readiness gate in the readiness step',
);

const liveRoleStep = extractNamedStep(
  releaseJob,
  'Require live three-role healthcare smoke',
);
for (const value of [
  '          EXPECTED_RELEASE_VERSION: ${{ github.sha }}',
  '          PATIENT_EMAIL: ${{ env.ROLE_PATIENT_EMAIL }}',
  '          CAREGIVER_EMAIL: ${{ env.ROLE_CAREGIVER_EMAIL }}',
  '          UNRELATED_EMAIL: ${{ env.ROLE_UNRELATED_EMAIL }}',
  '          bash tools/release/live-beta-smoke.sh > "$smoke_evidence"',
  '.status == "passed" and .release == $release',
]) {
  requireScopedText(
    liveRoleStep,
    value,
    'stable build must require the exact-main patient/caregiver/unrelated-user live smoke before signing',
  );
}

const signingStep = extractNamedStep(
  releaseJob,
  'Prepare founder-owned Android signing',
);
if (releaseJob.indexOf('      - name: Require live three-role healthcare smoke') >
  releaseJob.indexOf('      - name: Prepare founder-owned Android signing')) {
  fail('live three-role smoke must complete before founder-owned signing material is prepared');
}
requireScopedText(
  signingStep,
  '          WELLMATE_KEYSTORE_BASE64: ${{ secrets.WELLMATE_KEYSTORE_BASE64 }}',
  'stable release must keep founder-owned WellMate signing material protected',
);

const buildStep = extractNamedStep(releaseJob, 'Build exact-main release APKs');
requireScopedText(
  buildStep,
  "          LIFEMATE_REQUIRE_RELEASE_SIGNING: 'true'",
  'stable APK build step must keep founder-owned release signing fail-closed',
);

console.log(
  'Stable release workflow policy is scoped to executable release steps, synchronizes the worker, requires a live three-role healthcare smoke, and is bound to Environment beta.',
);
