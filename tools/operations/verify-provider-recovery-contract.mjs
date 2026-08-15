import fs from 'node:fs';

const providerGate = fs.readFileSync(
  'docs/operations/PROVIDER_RECOVERY_GATE.md',
  'utf8',
);
const logicalRunbook = fs.readFileSync(
  'docs/operations/BACKUP_RESTORE_MONITORING.md',
  'utf8',
);
const identityThreatModel = fs.readFileSync(
  'docs/security/IDENTITY_MEDICAL_LINKAGE_THREAT_MODEL.md',
  'utf8',
);
const restoreWorkflow = fs.readFileSync(
  '.github/workflows/postgres-restore-drill.yml',
  'utf8',
);

function fail(message) {
  console.error(`Provider recovery contract failure: ${message}`);
  process.exit(1);
}

function requireText(source, value, message) {
  if (!source.includes(value)) fail(message);
}

for (const [value, message] of [
  ['**RPO target:** 24 hours or better.', 'closed-beta RPO must stay explicit'],
  ['**RTO target:** 4 hours or better.', 'closed-beta RTO must stay explicit'],
  ['never run a destructive restore/failover experiment against the live production database', 'destructive production recovery drills must remain prohibited'],
  ['actual backup schedule/frequency', 'provider backup frequency must be evidenced'],
  ['actual retention window', 'provider retention must be evidenced'],
  ['whether PITR is available/enabled', 'PITR must be evidenced instead of inferred'],
  ['restore/clone to an isolated target', 'provider recovery must prefer an isolated target'],
  ['synthetic fixtures only', 'recovery verification must avoid real patient data'],
  ['identity-link key **reference/version** under #217', 'recovery must include the identity-link key reference/version'],
  ['The actual `LIFEMATE_IDENTITY_LINK_KEY` must remain outside PostgreSQL', 'protective identity-link key must stay outside database backup'],
  ['Do not rename that evidence PITR.', 'logical recovery must not be mislabeled as PITR'],
  ['#211 remains OPEN', 'source documentation must not auto-close provider evidence'],
]) requireText(providerGate, value, message);

for (const [value, message] of [
  ['Logical database recoverability', 'logical restore runbook must distinguish logical recovery'],
  ['Production managed backup availability', 'logical runbook must keep provider backup separate'],
  ['RPO target: 24 hours or better.', 'logical runbook must align to the recovery RPO'],
  ['RTO target: 4 hours or better', 'logical runbook must align to the recovery RTO'],
  ['It does **not** prove that the hosted production project currently has a provider snapshot available.', 'logical CI must not be presented as provider backup evidence'],
]) requireText(logicalRunbook, value, message);

for (const [value, message] of [
  ['provider runtime secret storage outside PostgreSQL', 'identity threat model must keep protective key outside PostgreSQL'],
  ['recovery ownership tied to #211 without copying the key into database backup', 'identity key recovery must remain bound to #211 without backup co-location'],
]) requireText(identityThreatModel, value, message);

for (const [value, message] of [
  ['schedule:', 'logical restore drill must retain an automatic schedule'],
  ['workflow_dispatch:', 'logical restore drill must remain manually runnable'],
  ['postgres:17.6', 'restore drill must retain PostgreSQL 17.6 parity'],
]) requireText(restoreWorkflow, value, message);

console.log(
  'Provider recovery gate preserves explicit RPO/RTO, isolated synthetic recovery, logical-vs-provider evidence separation, and external identity-key recovery boundaries.',
);
