import fs from 'node:fs';

const workflow = fs.readFileSync('.github/workflows/provider-safe-incident-drill.yml', 'utf8');

function fail(message) {
  console.error(`Provider-safe incident drill policy failure: ${message}`);
  process.exit(1);
}
function requireText(value, message) {
  if (!workflow.includes(value)) fail(message);
}
function forbidText(value, message) {
  if (workflow.toLowerCase().includes(value.toLowerCase())) fail(message);
}

for (const [value, message] of [
  ['workflow_dispatch:', 'drill must be manual only'],
  ['issues: write', 'drill must be able to route the induced failure to the response owner'],
  ['postgres:17.6-alpine', 'drill must use isolated PostgreSQL 17.6'],
  ['lifemate_ops_drill', 'drill target must be explicitly isolated'],
  ["test \"$GITHUB_EVENT_NAME\" = 'workflow_dispatch'", 'drill must fail closed outside manual dispatch'],
  ['revoke select on security.runtime_readiness_probe', 'drill must induce a provider-safe readiness failure'],
  ['permission denied|insufficient privilege', 'drill must prove detection rather than assume it'],
  ["--title 'OPS DRILL — Provider-safe incident detected'", 'detected failure must create a clearly synthetic incident'],
  ['--assignee "$GITHUB_REPOSITORY_OWNER"', 'detected failure must route to the repository owner'],
  ['No token, email, phone, Account/AppUser/Person identifier or healthcare data is copied into this alert.', 'owner alert must preserve the privacy boundary'],
  ['grant select on security.runtime_readiness_probe', 'drill must exercise rollback mitigation'],
  ["state='healthy'", 'drill must exercise a forward-fix recovery path'],
  ['runtime role security invariant regressed during drill', 'drill must re-verify security after recovery'],
  ['Close provider-safe incident after recovery', 'drill incident must only close after the recovery checks'],
  ['gh issue close "$incident_issue_number"', 'recovered drill incident must be closed explicitly'],
  ['source SHA:', 'drill evidence must correlate the exact source SHA'],
  ['PHI/PII/tokens/account/person identifiers in evidence: none', 'drill evidence must state the privacy boundary'],
]) requireText(value, message);

for (const [value, message] of [
  ['supabase.co', 'drill must not contact the hosted provider'],
  ['bwdvmniywyyijjauipnh', 'drill must not embed the production project ref'],
  ['LIFEMATE_READINESS_URL', 'drill must not use the production readiness endpoint'],
  ['SUPABASE_DB_URL', 'drill must not use a production/provider database URL'],
  ['curl ', 'drill must not call arbitrary HTTP endpoints'],
  ['wget ', 'drill must not call arbitrary HTTP endpoints'],
  ['secrets.', 'provider-safe drill must not require production secrets'],
]) forbidText(value, message);

const detectionIndex = workflow.indexOf('Detect, triage and route isolated failure');
const issueCreateIndex = workflow.indexOf('gh issue create');
const rollbackIndex = workflow.indexOf('Exercise rollback mitigation');
const invariantIndex = workflow.indexOf('Verify post-recovery security invariants');
const issueCloseIndex = workflow.indexOf('gh issue close "$incident_issue_number"');
if (
  detectionIndex < 0 || issueCreateIndex <= detectionIndex ||
  rollbackIndex <= issueCreateIndex || invariantIndex <= rollbackIndex ||
  issueCloseIndex <= invariantIndex
) {
  fail('alert creation and closure must be ordered detection -> alert -> rollback/recovery -> security verification -> close');
}

if (/^[ \t]+(push|pull_request|schedule):/m.test(workflow)) {
  fail('provider-safe incident drill itself must not run automatically');
}

console.log('Provider-safe incident drill is manual, isolated, owner-routed, privacy-safe, rollback-capable and provider-independent.');
