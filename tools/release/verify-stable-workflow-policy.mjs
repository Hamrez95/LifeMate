import fs from 'node:fs';

const workflowPath = '.github/workflows/main-final-android-release.yml';
const workflow = fs.readFileSync(workflowPath, 'utf8');

function requireText(value, message) {
  if (!workflow.includes(value)) {
    console.error(`Stable workflow policy failure: ${message}`);
    process.exit(1);
  }
}

requireText(
  "  verify-and-build:\n    if: ${{ github.event_name == 'workflow_dispatch' }}\n    runs-on: ubuntu-24.04\n    environment: beta\n",
  'verify-and-build must remain manual-only and bound to the beta Environment',
);
requireText(
  "test \"$CONFIRM_FOUNDATION_RELEASE\" = 'RELEASE-FOUNDATION-CLOSED'",
  'manual stable build must require explicit foundation closure confirmation',
);
requireText(
  'TELEMETRY_SMOKE_EMAIL: ${{ secrets.BETA_PATIENT_EMAIL }}',
  'stable build must require the beta patient smoke identity',
);
requireText(
  "LIFEMATE_REQUIRE_RELEASE_SIGNING: 'true'",
  'stable build must keep founder-owned release signing fail-closed',
);
requireText(
  '.databaseTransport == "transaction_pooler" and .transactionPoolerRequired == true',
  'stable build must keep the transaction-pooler readiness gate',
);

if (/verify-and-build:[\s\S]*?if:\s*\$\{\{\s*github\.event_name\s*==\s*'push'/.test(workflow)) {
  console.error('Stable workflow policy failure: verify-and-build must never run from a push event');
  process.exit(1);
}

console.log('Stable release workflow policy is fail-closed and bound to Environment beta.');
