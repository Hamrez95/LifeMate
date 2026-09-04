import fs from 'node:fs';

const mainDeployWorkflow = fs.readFileSync(
  '.github/workflows/main-edge-deploy.yml',
  'utf8',
);
const internalBetaWorkflow = fs.readFileSync(
  '.github/workflows/internal-beta-release.yml',
  'utf8',
);
const flutterWorkflow = fs.readFileSync('.github/workflows/flutter.yml', 'utf8');

function fail(message) {
  console.error(`Production deploy control-plane policy failure: ${message}`);
  process.exit(1);
}

function extractJob(source, jobName) {
  const lines = source.split('\n');
  const start = lines.findIndex((line) => line === `  ${jobName}:`);
  if (start === -1) fail(`missing ${jobName} job`);

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
  if (start === -1) fail(`missing ${stepName} step`);

  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^      - (?:name:|uses:)/.test(lines[index])) {
      end = index;
      break;
    }
  }
  return lines.slice(start, end).join('\n');
}

const deployJob = extractJob(mainDeployWorkflow, 'deploy-exact-main');

for (const [value, message] of [
  ['    environment: beta', 'production Edge deploy must be bound to the beta Environment'],
  ["    if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}", 'production Edge deploy must remain exact-main push only'],
]) {
  if (!deployJob.includes(value)) fail(message);
}

const guardStep = extractNamedStep(
  deployJob,
  'Require exact main deployment inputs',
);

for (const [value, message] of [
  ["          test \"$GITHUB_REF\" = 'refs/heads/main'", 'deploy must require main ref'],
  ['          test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', 'deploy must require exact checked-out SHA'],
  ["          test \"$GITHUB_REPOSITORY\" = 'Hamrez95/LifeMate'", 'deploy must bind to the canonical repository'],
  ["          test \"$SUPABASE_PROJECT_REF\" = 'bwdvmniywyyijjauipnh'", 'deploy must bind to the production Supabase project'],
  ['          test -n "$SUPABASE_ACCESS_TOKEN"', 'deploy must require the Supabase management credential'],
  ['          test -n "$SUPABASE_PUBLISHABLE_KEY"', 'deploy must require the publishable key used by smoke checks'],
]) {
  if (!guardStep.includes(value)) fail(message);
}

for (const forbidden of [
  'github.event.repository.private',
  'github.ref_protected',
]) {
  if (guardStep.includes(forbidden)) {
    fail(`production Edge deploy must not depend on a repository invariant that is false in LIVE GitHub: ${forbidden}`);
  }
}

if (deployJob.indexOf('      - name: Require exact main deployment inputs') >
  deployJob.indexOf('      - name: Deploy exact-main API telemetry readiness and worker')) {
  fail('control-plane guard must execute before production deployment');
}

for (const jobName of ['deploy-edge', 'live-role-smoke', 'build-android-internal']) {
  const job = extractJob(internalBetaWorkflow, jobName);
  if (!job.includes('    environment: beta')) {
    fail(`${jobName} must be bound to the beta Environment`);
  }
}

for (const forbidden of [
  'WELLMATE_KEYSTORE_BASE64',
  'CAREMATE_KEYSTORE_BASE64',
  'flutter build apk',
  'prepare-android-signing.sh',
]) {
  if (flutterWorkflow.includes(forbidden)) {
    fail(`generic Flutter CI must not expose a signing/build release path: ${forbidden}`);
  }
}

if (!flutterWorkflow.includes('Use the protected `internal-beta-release` workflow')) {
  fail('generic Flutter workflow must direct Android artifacts to the protected release workflow');
}

console.log(
  'Production Edge deploy is exact-main, canonical-repository/project bound, and protected by GitHub Environment beta; generic Flutter CI cannot mint release-signed APKs.',
);
