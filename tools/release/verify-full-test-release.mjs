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
requireText('bash tools/release/prepare-android-signing.sh', 'permanent signing preparation');
requireText('bash tools/release/verify-android-signing.sh', 'signature verification');
requireText('git rev-list --count HEAD', 'monotonic Android build number');
requireText('flutter build apk', 'APK output');
requireText('flutter build appbundle', 'AAB output');
requireText("'com.lifemate.wellmate'", 'WellMate package identity');
requireText("'com.lifemate.caremate'", 'CareMate package identity');
requireText('environment:"production-full-test"', 'full-test manifest environment');
requireText('features:{phoneOtp:true,womenCalendarPilot:true,googleAuth:false}', 'manifest feature flags');
requireText('SHA256SUMS.txt', 'artifact checksums');
requireText('manifest.json', 'immutable manifest');

assert.ok(
  !workflow.includes('SUPABASE_SERVICE_ROLE_KEY'),
  'mobile full-test workflow must never use service-role credentials',
);
assert.ok(
  !workflow.includes('--build-number="$GITHUB_RUN_NUMBER"'),
  'Android versionCode must not use workflow-local run number',
);

console.log('PASS: exact-main full-test mobile release contract');
