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

for (const spec of [
  'main-edge-deploy:push',
  'internal-beta-release:workflow_dispatch',
  'main-final-android-release:workflow_dispatch',
  'main-final-android-release:push',
  'postgres-schema:push',
  'edge-api:push',
  'ecosystem-workers:push',
  'privacy-lifecycle-contract:push',
  'identity-link-retirement-policy:push',
  'workstation-backup-policy:push',
  'runtime-onboarding-control-policy:push',
  'critical-workflow-failure-drill:workflow_dispatch',
]) {
  requireText(monitor, `'${spec}'`, `critical workflow/event allow-list is missing ${spec}`);
}

for (const [value, message] of [
  ["- cron: '7,22,37,52 * * * *'", 'critical workflow monitor must poll every 15 minutes'],
  ['workflow_dispatch:', 'critical workflow monitor must support manual evidence runs'],
  ['actions: read', 'monitor must be able to read workflow results'],
  ['issues: write', 'monitor must have narrowly scoped issue-write permission'],
  ['--branch main', 'operational polling must be scoped to main'],
  ['--event "$event"', 'workflow event type must be part of the monitored identity'],
  ['--status completed', 'monitor must evaluate only completed runs'],
  ['failure|timed_out|startup_failure|action_required', 'critical failure conclusions must be explicit'],
  ['--state open', 'alert routing must deduplicate against open incidents'],
  ['gh issue comment "$issue_number"', 'repeated failures must update the same incident'],
  ['gh issue create', 'first critical failure must create an incident'],
  ['--assignee "$GITHUB_REPOSITORY_OWNER"', 'critical incidents must route to the repository owner'],
  ['Source SHA:', 'alert must correlate the exact source SHA'],
  ['This alert contains workflow metadata only.', 'alert must state its privacy-minimized scope'],
  ['No response body, token, secret, email, phone, Account/AppUser/Person identifier, healthcare payload or database content is copied into the incident.', 'critical alert must preserve the privacy boundary'],
  ["if [ \"$conclusion\" = 'success' ] && [ -n \"$issue_number\" ]; then", 'successful later runs must drive recovery closure'],
  ['gh issue close "$issue_number"', 'recovered incidents must close'],
  ['OPS DRILL — Critical workflow alert routing', 'synthetic drill alerts must be clearly distinguished from real incidents'],
]) requireText(monitor, value, message);

for (const forbidden of [
  'workflow_run:',
  'secrets.',
  'SUPABASE_ACCESS_TOKEN',
  'BETA_PATIENT_EMAIL',
  'BETA_PATIENT_PASSWORD',
  'curl ',
  'wget ',
]) {
  forbidText(monitor, forbidden, `critical alert monitor must not depend on chained workflow events, runtime/provider secrets or payload endpoints: ${forbidden}`);
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

console.log('Critical main deployment/release workflow failures are polled, owner-routed, deduplicated, privacy-minimized and recovery-closed; drill remains manual/provider-safe.');
