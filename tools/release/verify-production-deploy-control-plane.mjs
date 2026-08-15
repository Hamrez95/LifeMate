import fs from 'node:fs';

const workflowPath = '.github/workflows/main-edge-deploy.yml';
const workflow = fs.readFileSync(workflowPath, 'utf8');

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

const deployJob = extractJob(workflow, 'deploy-exact-main');

for (const [value, message] of [
  ['    environment: beta', 'production Edge deploy must be bound to the beta Environment'],
  ["    if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}", 'production Edge deploy must remain exact-main push only'],
]) {
  if (!deployJob.includes(value)) fail(message);
}

const guardStep = extractNamedStep(
  deployJob,
  'Require exact main and protected deployment inputs',
);

for (const [value, message] of [
  ["          test \"$GITHUB_REF\" = 'refs/heads/main'", 'deploy must require main ref'],
  ['          test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', 'deploy must require exact checked-out SHA'],
  ["          test \"${{ github.event.repository.private }}\" = 'true'", 'deploy must fail closed while repository visibility is public'],
  ["          test \"${{ github.ref_protected }}\" = 'true'", 'deploy must fail closed while main is not protected by branch protection/ruleset'],
]) {
  if (!guardStep.includes(value)) fail(message);
}

if (deployJob.indexOf('      - name: Require exact main and protected deployment inputs') >
  deployJob.indexOf('      - name: Deploy exact-main API telemetry readiness and worker')) {
  fail('control-plane guard must execute before production deployment');
}

console.log(
  'Production Edge deployment is source-bound to private protected main and GitHub Environment beta.',
);
