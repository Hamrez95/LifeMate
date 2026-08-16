import fs from 'node:fs';

const workflowPath = '.github/workflows/production-health-monitor.yml';
const workflow = fs.readFileSync(workflowPath, 'utf8');
const runbook = fs.readFileSync('docs/operations/production-health-alerting.md', 'utf8');

function fail(message) {
  console.error(`Production health alert policy failure: ${message}`);
  process.exit(1);
}

function requireText(source, value, message) {
  if (!source.includes(value)) fail(message);
}

function rejectText(source, value, message) {
  if (source.includes(value)) fail(message);
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

requireText(workflow, "    - cron: '*/15 * * * *'", '15-minute production health schedule must remain enabled');
requireText(workflow, '  issues: write', 'monitor must have narrowly scoped issue-write permission for owner alerts');
requireText(workflow, '      exercise_alert:', 'provider-safe manual alert drill input is required');

const readinessJob = extractJob(workflow, 'lifemate-application-readiness');
requireText(
  readinessJob,
  "    if: ${{ github.event_name != 'workflow_dispatch' || !inputs.exercise_alert }}",
  'synthetic drill must skip the production readiness job entirely',
);

const readinessStep = extractNamedStep(
  readinessJob,
  'Check production Edge and restricted database dependency',
);
for (const [value, message] of [
  ['.status == "ok"', 'readiness must require status ok'],
  ['.database == "application_ready"', 'readiness must require application-ready database'],
  ['.role == "lifemate_edge_runtime"', 'readiness must verify restricted runtime role'],
  ['.mode == "lightweight"', 'recurring monitor must stay lightweight'],
  ['.durationMs | type == "number"', 'readiness must bound probe duration'],
  ['.version | type == "string"', 'readiness must retain release identity'],
]) requireText(readinessStep, value, message);

const alertStep = extractNamedStep(
  readinessJob,
  'Route readiness failure to the repository owner',
);
for (const [value, message] of [
  ['        if: ${{ failure() }}', 'real alert routing must run on readiness failure'],
  ["alert_title='OPS ALERT — Production readiness failed'", 'real alert must use the canonical deduplicated title'],
  ['--state open', 'real alert must search only open incidents for deduplication'],
  ['gh issue comment "$issue_number"', 'repeat failures must update the existing incident'],
  ['gh issue create', 'first failure must create a real owner-visible incident'],
  ['--assignee "$GITHUB_REPOSITORY_OWNER"', 'critical readiness alert must be assigned to the repository owner'],
  ['No response body, token, email, phone, account/person identifier, or healthcare payload is copied into this alert.', 'alert body must state its privacy boundary'],
  ['Source SHA:', 'alert must identify source/release SHA'],
]) requireText(alertStep, value, message);

for (const forbidden of [
  'cat "$response_file"',
  'jq . "$response_file"',
  'Authorization:',
  'SUPABASE_ACCESS_TOKEN',
  'BETA_PATIENT_EMAIL',
  'BETA_PATIENT_PASSWORD',
]) {
  rejectText(alertStep, forbidden, `alert routing must not expose sensitive/runtime response material: ${forbidden}`);
}

const recoveryStep = extractNamedStep(
  readinessJob,
  'Close recovered production readiness alert',
);
requireText(recoveryStep, '        if: ${{ success() }}', 'healthy probe must close a prior open readiness incident');
requireText(recoveryStep, 'gh issue comment "$issue_number"', 'recovery must record evidence before closure');
requireText(recoveryStep, 'gh issue close "$issue_number"', 'recovered readiness incident must be closed');

const drillJob = extractJob(workflow, 'alert-routing-drill');
requireText(
  drillJob,
  "    if: ${{ github.event_name == 'workflow_dispatch' && inputs.exercise_alert }}",
  'alert drill must be explicit manual dispatch only',
);
const createDrillStep = extractNamedStep(
  drillJob,
  'Create a provider-safe synthetic alert',
);
for (const [value, message] of [
  ["alert_title='OPS DRILL — Production readiness alert routing'", 'drill must use a clearly synthetic title'],
  ['This drill does not call the production readiness endpoint and contains no production/user payload.', 'drill must explicitly avoid production probing/payloads'],
  ['--assignee "$GITHUB_REPOSITORY_OWNER"', 'drill must prove the intended owner route'],
  ['issue_number="${issue_url##*/}"', 'drill must capture the created issue for deterministic cleanup'],
]) requireText(createDrillStep, value, message);
rejectText(createDrillStep, 'curl ', 'synthetic alert drill must not call the production endpoint');

const closeDrillStep = extractNamedStep(
  drillJob,
  'Auto-close successful synthetic alert drill',
);
requireText(closeDrillStep, 'gh issue comment "$ISSUE_NUMBER"', 'drill must record completion evidence');
requireText(closeDrillStep, 'gh issue close "$ISSUE_NUMBER"', 'drill must clean up its synthetic incident');

for (const [value, message] of [
  ['## Severity, owner and required action', 'runbook must include a severity/action/owner matrix'],
  ['| SEV-1 |', 'runbook must define critical severity handling'],
  ['| SEV-2 |', 'runbook must define major operational severity handling'],
  ['| SEV-3 |', 'runbook must define warning severity handling'],
  ['The repository owner is the default incident response owner during the closed beta.', 'runbook must name the default response owner'],
  ['only the Founder/release operator may declare a production rollback/forward-fix, pause/resume new onboarding, change emergency traffic/admission controls', 'runbook must define emergency authority'],
  ['No incident action may disable or weaken patient/caregiver authorization, consent checks, idempotency, audit requirements, restricted database roles, signing verification or the stable-release gates.', 'runbook must preserve security and release invariants during incidents'],
  ['## Closed-beta support and escalation', 'runbook must define the closed-beta escalation process'],
  ['Any suspected cross-user disclosure, consent bypass or unexplained healthcare data loss is SEV-1 until disproven.', 'sensitive correctness/security reports must fail closed to SEV-1'],
  ['docs/operations/beta-onboarding-control.md', 'runbook must point to the no-deploy onboarding pause path'],
  ['Never request or move raw healthcare payloads into GitHub, Trello, chat or an external alert provider.', 'support escalation must preserve the privacy boundary'],
  ['start, detection, acknowledgement, mitigation, recovery and post-verification UTC timestamps', 'incident evidence must preserve the complete response timeline'],
]) requireText(runbook, value, message);

console.log('Production readiness monitoring is bound to redacted owner alerts, recovery closure, provider-safe drills, and an explicit closed-beta escalation contract.');
