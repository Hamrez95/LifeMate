import assert from 'node:assert/strict';
import fs from 'node:fs';

const workflowPath = '.github/workflows/full-test-release.yml';
const workflow = fs.readFileSync(workflowPath, 'utf8');

const requireText = (token, label) => {
  assert.ok(workflow.includes(token), `${label}: missing ${JSON.stringify(token)}`);
};

requireText('workflow_dispatch:', 'explicit manual dispatch');
requireText("test \"$GITHUB_REF\" = 'refs/heads/main'", 'exact-main source guard');
requireText("test \"$CONFIRM_RELEASE\" = 'BUILD-FULL-TEST-RELEASE'", 'human release confirmation');
requireText('https://bwdvmniywyyijjauipnh.supabase.co/functions/v1/lifemate-api', 'production API endpoint');
requireText('--dart-define="ENABLE_PHONE_OTP=true"', 'Phone OTP enabled');
requireText('--dart-define="ENABLE_WOMEN_CALENDAR_PILOT=true"', 'Women Health pilot enabled');
requireText('--dart-define="ENABLE_GOOGLE_AUTH=false"', 'unverified Google auth remains fail-closed');
requireText('(cd "$api" && deno task test --allow-read=../..)', 'production API unit test suite');
requireText('node tools/release/verify-production-db-contract.mjs', 'production DB contract preflight');
requireText('supabase functions deploy lifemate-api', 'exact-main API deployment');
requireText('LIFEMATE_RELEASE_VERSION', 'deployed API release identity');
requireText('.version == $version', 'deployed API exact-main verification');
requireText('bash tools/release/prepare-android-signing.sh', 'permanent signing preparation');
requireText('bash tools/release/verify-android-signing.sh', 'signature verification');
requireText('git rev-list --count HEAD', 'monotonic Android build number');
requireText('flutter build apk --split-per-abi', 'smaller ABI-specific APK outputs');
requireText('app-arm64-v8a-release.apk', 'arm64 APK output');
requireText('app-armeabi-v7a-release.apk', '32-bit ARM APK output');
requireText('app-x86_64-release.apk', 'x86_64 APK output');
requireText('flutter build appbundle', 'AAB output');
requireText('flutter build web', 'web output');
requireText('wellmate-arm64-${{ github.sha }}', 'small WellMate artifact');
requireText('caremate-arm64-${{ github.sha }}', 'small CareMate artifact');
requireText('wellmate-web-$RELEASE_NAME-$short_sha.tar.gz', 'WellMate web bundle');
requireText('caremate-web-$RELEASE_NAME-$short_sha.tar.gz', 'CareMate web bundle');
requireText("'com.lifemate.wellmate'", 'WellMate package identity');
requireText("'com.lifemate.caremate'", 'CareMate package identity');
requireText('environment:"production-full-test"', 'full-test manifest environment');
requireText('preferredAndroidAbi:"arm64-v8a"', 'preferred Android ABI manifest field');
requireText('features:{phoneOtp:true,womenCalendarPilot:true,googleAuth:false}', 'manifest feature flags');
requireText('SHA256SUMS.txt', 'artifact checksums');
requireText('manifest.json', 'immutable manifest');

const preflightIndex = workflow.indexOf(
  'node tools/release/verify-production-db-contract.mjs',
);
const deployIndex = workflow.indexOf('supabase functions deploy lifemate-api');
assert.ok(
  preflightIndex >= 0 && deployIndex >= 0 && preflightIndex < deployIndex,
  'production DB contract preflight must run before exact-main API deployment',
);

assert.ok(
  !workflow.includes('SUPABASE_SERVICE_ROLE_KEY'),
  'mobile full-test workflow must never use service-role credentials',
);
assert.ok(
  !workflow.includes('--build-number="$GITHUB_RUN_NUMBER"'),
  'Android versionCode must not use workflow-local run number',
);
assert.ok(
  !workflow.includes('flutter build apk "${build_args[@]}"'),
  'fat universal APK must not replace split APKs in the full-test path',
);
assert.ok(
  !workflow.includes('deno fmt --check --config "$api/deno.json" "$api"'),
  'release verification must not fail on pre-existing formatting outside its diff',
);

console.log('PASS: exact-main backend + DB preflight + split Android + web full-test contract');
