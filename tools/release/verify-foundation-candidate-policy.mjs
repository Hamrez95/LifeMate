import fs from 'node:fs';

const workflow = fs.readFileSync(
  '.github/workflows/foundation-candidate-qualify.yml',
  'utf8',
);

function fail(message) {
  console.error(`Foundation candidate policy failure: ${message}`);
  process.exit(1);
}
function requireText(value, message) {
  if (!workflow.includes(value)) fail(message);
}
function forbidText(value, message) {
  if (workflow.toLowerCase().includes(value.toLowerCase())) fail(message);
}

for (const [value, message] of [
  ['workflow_dispatch:', 'candidate qualification must be manual only'],
  ['    environment: beta', 'qualification must be bound to the beta Environment'],
  ["test \"$GITHUB_REF\" = 'refs/heads/main'", 'qualification must require main'],
  ['test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', 'qualification must require exact checked-out SHA'],
  ["test \"${{ github.event.repository.private }}\" = 'true'", 'qualification must fail while repository is public'],
  ["test \"${{ github.ref_protected }}\" = 'true'", 'qualification must fail while main is unprotected'],
  ['gh issue view 210', 'qualification must require the release-control gate decision'],
  ['--workflow main-edge-deploy.yml', 'qualification must prove exact-main API/telemetry/readiness/worker synchronization'],
  ['--json databaseId,headSha,conclusion', 'main-edge lookup must bind run ID, exact SHA and conclusion'],
  ['select(.headSha ==', 'main-edge evidence must filter the exact source SHA'],
  ['.conclusion == \\"success\\"', 'main-edge evidence must require a successful run'],
  ['.databaseTransport == "transaction_pooler"', 'qualification must require transaction-pooler transport'],
  ['.transactionPoolerRequired == true', 'qualification must require transaction-pooler enforcement'],
  ['.name == "internal-beta-release"', 'source artifact must come from internal-beta-release'],
  ['.event == "workflow_dispatch"', 'source artifact must come from an explicit manual release'],
  ['.headBranch == "main"', 'source internal release must be from main'],
  ['.headSha == $sha', 'source internal release must match exact candidate SHA'],
  ['.conclusion == "success"', 'source internal release must have completed successfully'],
  ['live-role-smoke-$short_sha', 'qualification must require the live-role smoke artifact'],
  ['.roles.patient | length > 0', 'patient live-role evidence must be non-empty'],
  ['.roles.caregiver | length > 0', 'caregiver live-role evidence must be non-empty'],
  ['.roles.unrelated | length > 0', 'unrelated live-role evidence must be non-empty'],
  ['.signing == "founder-owned stable release keystores"', 'source bundle must prove founder signing'],
  ['sha256sum "$wellmate_apk"', 'qualification must independently verify WellMate artifact hash'],
  ['sha256sum "$caremate_apk"', 'qualification must independently verify CareMate artifact hash'],
  ['extract-android-apk-metadata.sh', 'qualification must extract min/target SDK from exact APK bytes'],
  ['rebuildPerformed:false', 'qualification manifest must record that no rebuild occurred'],
  ['foundation-candidate-manifest.json', 'qualification must emit a device-QA manifest'],
  ['lifemate-foundation-candidate-${{ github.sha }}', 'qualified bundle must be immutable-SHA named'],
]) requireText(value, message);

for (const [value, message] of [
  ['flutter build', 'qualification must never rebuild the candidate APKs'],
  ['gradlew assemble', 'qualification must never rebuild Android artifacts'],
  ['run_live_role_smoke', 'qualification must not expose a live-role-smoke bypass input'],
  ['needs.live-role-smoke.result == \'skipped\'', 'skipped live-role smoke must never qualify'],
  ['SUPABASE_ACCESS_TOKEN', 'qualification must not need a provider management credential'],
  ['WELLMATE_KEYSTORE_BASE64', 'qualification must not reconstruct signing material'],
  ['CAREMATE_KEYSTORE_BASE64', 'qualification must not reconstruct signing material'],
]) forbidText(value, message);

if (/^[ \t]+(push|pull_request|schedule):/m.test(workflow)) {
  fail('Foundation candidate qualification must not run automatically');
}

const mainEdgeIndex = workflow.indexOf(
  'Require successful exact-main production Edge synchronization',
);
const poolerIndex = workflow.indexOf(
  'Require transaction-pooler readiness on exact main',
);
const internalRunIndex = workflow.indexOf(
  'Verify internal beta run belongs to exact main',
);
const smokeIndex = workflow.indexOf(
  'Verify live patient caregiver unrelated evidence',
);
const bundleIndex = workflow.indexOf(
  'Verify founder-signed bundle and artifact hashes',
);
const uploadIndex = workflow.indexOf(
  'Upload qualified exact-byte Foundation candidate',
);
if (
  mainEdgeIndex < 0 || poolerIndex <= mainEdgeIndex ||
  internalRunIndex <= poolerIndex || smokeIndex <= internalRunIndex ||
  bundleIndex <= smokeIndex || uploadIndex <= bundleIndex
) {
  fail('candidate gates must execute before evidence packaging/upload in dependency order');
}

console.log(
  'Foundation candidate qualification is manual, exact-main, pooler-gated, live-role proven, founder-signed, exact-byte and non-rebuilding.',
);
