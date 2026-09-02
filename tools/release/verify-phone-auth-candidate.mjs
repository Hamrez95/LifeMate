import assert from 'node:assert/strict';
import fs from 'node:fs';

const workflowPath = '.github/workflows/phone-auth-candidate-release.yml';
const workflow = fs.readFileSync(workflowPath, 'utf8');
const stable = fs.readFileSync('.github/workflows/main-final-android-release.yml', 'utf8');
const serviceRoleCredentialName = ['SUPABASE', 'SERVICE', 'ROLE', 'KEY'].join('_');

const requireText = (source, token, label) => {
  assert.ok(source.includes(token), `${label}: missing ${JSON.stringify(token)}`);
};

requireText(workflow, 'workflow_dispatch:', 'explicit candidate dispatch');
requireText(workflow, "test \"$GITHUB_REF\" = 'refs/heads/main'", 'exact-main source guard');
requireText(workflow, "test \"$CONFIRM_CANDIDATE\" = 'BUILD-PHONE-AUTH-CANDIDATE'", 'human dispatch confirmation');
requireText(workflow, '--dart-define="ENABLE_PHONE_OTP=true"', 'phone OTP build flag');
requireText(workflow, '--dart-define="ENABLE_GOOGLE_AUTH=false"', 'Google auth remains fail-closed');
requireText(workflow, 'https://bwdvmniywyyijjauipnh.supabase.co/functions/v1/lifemate-api', 'production API endpoint');
requireText(workflow, 'bash tools/release/prepare-android-signing.sh', 'founder signing preparation');
requireText(workflow, 'bash tools/release/verify-android-signing.sh', 'release signature verification');
requireText(workflow, 'wellmate/build/app/outputs/flutter-apk/app-release.apk', 'WellMate release APK');
requireText(workflow, 'caremate/build/app/outputs/flutter-apk/app-release.apk', 'CareMate release APK');
requireText(workflow, 'environment:"production-phone-auth-candidate"', 'candidate environment manifest');
requireText(workflow, 'auth:{phoneOtp:true,google:false}', 'manifest auth flags');
requireText(workflow, '--arg commit "$GITHUB_SHA"', 'immutable commit manifest');
requireText(workflow, 'build_number="$(git rev-list --count HEAD)"', 'candidate Android versionCode follows canonical release sequence');
requireText(workflow, 'PHONE_AUTH_BUILD_NUMBER=$build_number', 'candidate build number is preserved for manifest evidence');
requireText(workflow, '--arg buildNumber "$PHONE_AUTH_BUILD_NUMBER"', 'immutable canonical build number manifest');
requireText(workflow, 'sha256sum', 'artifact digest manifest');

assert.ok(
  !workflow.includes('build_number="$GITHUB_RUN_NUMBER"'),
  'workflow run number must not be used as Android versionCode because it can make an update look like a downgrade',
);
assert.ok(
  !workflow.includes(serviceRoleCredentialName),
  'mobile candidate workflow must never reference service-role credentials',
);
assert.ok(
  !workflow.includes('ENABLE_PHONE_OTP=false'),
  'Phone Auth candidate must not compile the product flow disabled',
);

// Candidate activation must not silently flip the stable/final release path.
requireText(stable, "ENABLE_PHONE_OTP: 'false'", 'stable release remains gated pending device QA');

console.log('PASS: signed exact-main Phone Auth candidate release contract');