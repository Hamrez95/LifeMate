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

const readinessStep = extractNamedStep(
  releaseJob,
  'Require restricted readiness role on transaction pooler',
);
requireScopedText(
  readinessStep,
  '.databaseTransport == "transaction_pooler" and .transactionPoolerRequired == true',
  'stable build must keep the transaction-pooler readiness gate in the readiness step',
);

const buildStep = extractNamedStep(releaseJob, 'Build exact-main release APKs');
requireScopedText(
  buildStep,
  "          LIFEMATE_REQUIRE_RELEASE_SIGNING: 'true'",
  'stable APK build step must keep founder-owned release signing fail-closed',
);

console.log(
  'Stable release workflow policy is scoped to executable release steps and bound to Environment beta.',
);
