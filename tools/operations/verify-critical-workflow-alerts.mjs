import fs from 'node:fs';

const monitor = fs.readFileSync('.github/workflows/critical-workflow-alerts.yml', 'utf8');
const drill = fs.readFileSync('.github/workflows/critical-workflow-failure-drill.yml', 'utf8');

function fail(message) {
  console.error(`Critical workflow alert policy failure: ${message}`);
  process.exit(1);
}
function requireText(source, value, message) {
  if (!source.includes(value)) fail(message);
}
function forbidText(source, value, message) {
  if (source.toLowerCase().includes(value.toLowerCase())) fail(message);
}

for (const workflowName of [
  'main-edge-deploy',
  'internal-beta-release',
  'main-final-android-release',
  'postgres-schema',
  'edge-api',
  'ecosystem-workers',
  'privacy-lifecycle-contract',
  'identity-link-retirement-policy',
  'workstation-backup-policy',
  'runtime-onboarding-control-policy',
  'critical-workflow-failure-drill',
]) {
  requireText(monitor, `      - ${workflowName}`, `critical workflow allow-list is missing ${workflowName}`);
}

for (const [value, message] of [
  ['workflow_run:', 'monitor must use workflow_run completion events'],
  ['branches: [main]', 'operational alerts must be scoped to main'],
  ['types: [completed]', 'monitor must wait for a completed critical workflow'],
  ['issues: write', 'monitor must have narrowly scoped issue-write permission'],
  ["github.event.workflow_run.event != 'pull_request'", 'ordinary PR validation failures must not create operational incidents'],
  ['["failure","timed_out","startup_failure","action_required"]', 'critical failure conclusions must be explicit'],
  ['--state open', 'alert routing must deduplicate against open incidents'],
  ['gh issue comment "$existing"', 'repeated failures must update the same incident'],
  ['gh issue create', 'first critical failure must create an incident'],
  ['--assignee "$GITHUB_REPOSITORY_OWNER"', 'critical incidents must route to the repository owner'],
  ['Source SHA:', 'alert must correlate the exact source SHA'],
  ['This alert contains workflow metadata only.', 'alert must state its privacy-minimized scope'],
  ['No response body, token, secret, email, phone, Account/AppUser/Person identifier, healthcare payload or database content is copied into the incident.', 'critical alert must preserve the privacy boundary'],
  ["github.event.workflow_run.conclusion == 'success'", 'successful later runs must drive recovery closure'],
  ['gh issue close "$issue_number"', 'recovered incidents must close'],
  ['OPS DRILL — Critical workflow alert routing', 'synthetic drill alerts must be clearly distinguished from real incidents'],
]) requireText(monitor, value, message);

for (const forbidden of [
  'secrets.',
  'SUPABASE_ACCESS_TOKEN',
  'BETA_PATIENT_EMAIL',
  'BETA_PATIENT_PASSWORD',
  'curl ',
  'wget ',
]) {
  forbidText(monitor, forbidden, `critical alert monitor must not consume runtime/provider secrets or payload endpoints: ${forbidden}`);
}

for (const [value, message] of [
  ['workflow_dispatch:', 'synthetic failure drill must be manual only'],
  ['type: choice', 'drill outcome must be explicit'],
  ['- failure', 'drill must support a deliberate failed workflow completion'],
  ['- success', 'drill must support a deliberate recovery completion'],
  ["test \"$GITHUB_EVENT_NAME\" = 'workflow_dispatch'", 'drill must fail closed outside manual dispatch'],
  ['Expected synthetic failure for critical workflow alert routing drill.', 'failure must be clearly synthetic'],
  ['Synthetic recovery result completed successfully.', 'drill must provide a recovery completion'],
]) requireText(drill, value, message);

if (/^[ \t]+(push|pull_request|schedule):/m.test(drill)) {
  fail('synthetic critical workflow drill must not run automatically');
}
for (const forbidden of ['secrets.', 'supabase.co', 'curl ', 'wget ', 'DATABASE_URL']) {
  forbidText(drill, forbidden, `synthetic drill must remain provider-safe and secret-free: ${forbidden}`);
}

console.log('Critical main deployment/release workflow failures are owner-routed, deduplicated, privacy-minimized and recovery-closed; drill remains manual/provider-safe.');
