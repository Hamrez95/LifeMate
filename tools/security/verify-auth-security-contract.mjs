import fs from 'node:fs';

const config = fs.readFileSync('supabase/config.toml', 'utf8');
const featureFlags = fs.readFileSync(
  'packages/lifemate_client/lib/src/feature_flags.dart',
  'utf8',
);
const authPolicy = fs.readFileSync(
  'packages/lifemate_client/lib/src/auth_security_policy.dart',
  'utf8',
);
const authUi = fs.readFileSync(
  'packages/lifemate_client/lib/src/experience_auth.dart',
  'utf8',
);
const recoveryUi = fs.readFileSync(
  'packages/lifemate_client/lib/src/experience_recovery.dart',
  'utf8',
);
const phoneAuthUi = fs.readFileSync(
  'packages/lifemate_client/lib/src/experience_phone_auth.dart',
  'utf8',
);
const authClient = fs.readFileSync(
  'packages/lifemate_client/lib/src/lifemate_auth.dart',
  'utf8',
);
const accountSecurity = fs.readFileSync(
  'packages/lifemate_client/lib/src/account_security.dart',
  'utf8',
);

function fail(message) {
  console.error(`Auth security contract failure: ${message}`);
  process.exit(1);
}

function requireMatch(source, pattern, message) {
  if (!pattern.test(source)) fail(message);
}

function rejectMatch(source, pattern, message) {
  if (pattern.test(source)) fail(message);
}

// Local/self-hosted defaults must not be materially weaker than the mobile
// contract. Hosted production settings are a separate provider evidence gate.
requireMatch(
  config,
  /^minimum_password_length\s*=\s*12\s*$/m,
  'local Auth minimum password length must match the 12-character beta policy',
);
requireMatch(
  config,
  /^enable_refresh_token_rotation\s*=\s*true\s*$/m,
  'refresh-token rotation must stay enabled locally',
);
requireMatch(
  config,
  /^refresh_token_reuse_interval\s*=\s*10\s*$/m,
  'refresh-token reuse interval must remain explicitly bounded',
);
requireMatch(
  config,
  /^enable_anonymous_sign_ins\s*=\s*false\s*$/m,
  'anonymous Auth users must remain disabled',
);
requireMatch(
  config,
  /^jwt_expiry\s*=\s*3600\s*$/m,
  'local session JWT lifetime must stay explicit and bounded',
);
requireMatch(
  config,
  /Hosted production Auth settings are[\s\S]*separate live evidence under Foundation #215/,
  'local config must not be presented as hosted production Auth evidence',
);

for (const [flag, message] of [
  [
    'ENABLE_GOOGLE_AUTH',
    'Google Auth must remain compile-time fail-closed by default',
  ],
  [
    'ENABLE_PHONE_OTP',
    'phone OTP must remain compile-time fail-closed by default',
  ],
]) {
  requireMatch(
    featureFlags,
    new RegExp(`${flag.replaceAll('_', '\\_')}[\\s\\S]{0,120}defaultValue:\\s*false`),
    message,
  );
}

requireMatch(
  authPolicy,
  /static const minimumLength\s*=\s*12\s*;/,
  'shared password policy must require at least 12 characters',
);
requireMatch(
  authPolicy,
  /RegExp\(r'\[a-z\]'\)\.hasMatch\(value\)/,
  'shared password policy must require lowercase letters',
);
requireMatch(
  authPolicy,
  /RegExp\(r'\[A-Z\]'\)\.hasMatch\(value\)/,
  'shared password policy must require uppercase letters',
);
requireMatch(
  authPolicy,
  /RegExp\(r'\[0-9\]'\)\.hasMatch\(value\)/,
  'shared password policy must require a digit',
);
requireMatch(
  authPolicy,
  /_symbols\.contains/,
  'shared password policy must require an approved symbol',
);
requireMatch(
  authUi,
  /isSignUp[\s\S]{0,260}LifeMatePasswordPolicy\.validationMessage\(/,
  'signup must use the centralized password creation policy',
);
requireMatch(
  authUi,
  /:\s*\(value\?\.length\s*\?\?\s*0\)\s*>=\s*8/,
  'existing password sign-in validation must remain backward compatible',
);
requireMatch(
  recoveryUi,
  /LifeMatePasswordPolicy\.validationMessage\(/,
  'password recovery must use the centralized password creation policy',
);
requireMatch(
  recoveryUi,
  /safeRecoveryAuthMessage\([\s\S]{0,120}error\.message/,
  'password recovery must collapse provider failures into safe user copy',
);
rejectMatch(
  recoveryUi,
  /_error\s*=\s*error\.message|setState\([\s\S]{0,120}_error\s*=\s*error\.message/,
  'password recovery must never render raw Supabase Auth provider messages',
);
requireMatch(
  authUi,
  /key:\s*ValueKey\('auth-confirm-password'\)[\s\S]{0,2400}value\s*==\s*_password\.text/,
  'signup must retain password confirmation',
);
requireMatch(
  authUi,
  /onPressed:\s*_busy\s*\?\s*null\s*:\s*_sendPasswordReset/,
  'password recovery entry point must remain wired',
);
requireMatch(
  authUi,
  /LifeMateFeatureFlags\.googleAuthEnabled[\s\S]{0,4200}key:\s*ValueKey\('auth-google'\)/,
  'Google button must remain behind the compile-time feature flag',
);
requireMatch(
  authUi,
  /LifeMateFeatureFlags\.phoneOtpEnabled[\s\S]{0,1200}_PhoneOtpButton/,
  'phone OTP button must remain behind the compile-time feature flag',
);
requireMatch(
  phoneAuthUi,
  /ValueKey\('auth-phone-intent-signin'\)[\s\S]{0,400}LifeMatePhoneOtpIntent\.signIn/,
  'phone OTP UI must expose an explicit non-creating returning-user sign-in intent',
);
requireMatch(
  phoneAuthUi,
  /ValueKey\('auth-phone-intent-signup'\)[\s\S]{0,400}LifeMatePhoneOtpIntent\.signUp/,
  'phone OTP UI must expose account creation only as an explicit signup intent',
);
requireMatch(
  phoneAuthUi,
  /New signup never auto-merges an existing account/,
  'phone signup UI must explicitly warn existing users that signup does not auto-merge accounts',
);
requireMatch(
  authClient,
  /signInWithOtp\([\s\S]{0,220}shouldCreateUser:\s*shouldCreatePhoneUser\(intent\)/,
  'phone OTP requests must pass explicit account-creation intent to Supabase Auth',
);
requireMatch(
  authClient,
  /shouldCreatePhoneUser\(LifeMatePhoneOtpIntent intent\)[\s\S]{0,120}intent\s*==\s*LifeMatePhoneOtpIntent\.signUp/,
  'returning-user phone sign-in must remain non-creating',
);
requireMatch(
  authClient,
  /LifeMateNumbers\.toLatin\(token\)\.trim\(\)/,
  'phone OTP verification must canonicalize localized digits before validation',
);
requireMatch(
  accountSecurity,
  /phoneLinkingEnabled\s*=\s*LifeMateFeatureFlags\.phoneOtpEnabled/,
  'account phone linking must remain behind the fail-closed phone OTP flag',
);
requireMatch(
  accountSecurity,
  /updateUser\(UserAttributes\(phone:\s*phoneE164\)\)/,
  'phone linking must update the current authenticated user instead of starting a new signup',
);
requireMatch(
  accountSecurity,
  /verifyOTP\([\s\S]{0,180}type:\s*OtpType\.phoneChange/,
  'phone linking must verify with the dedicated phone-change OTP type',
);
requireMatch(
  accountSecurity,
  /LifeMateNumbers\.toLatin\(_phoneOtpController\.text\)\.trim\(\)/,
  'phone-change verification must canonicalize localized OTP digits',
);

// Signup must not disclose whether an email already belongs to an account.
requireMatch(
  authUi,
  /response\.session\s*==\s*null[\s\S]{0,500}_genericSignupMessage\(\)/,
  'non-session signup must use existence-neutral confirmation copy',
);
requireMatch(
  authUi,
  /_mode\s*==\s*_AuthMode\.signUp[\s\S]{0,240}user already registered[\s\S]{0,500}_genericSignupMessage\(\)/,
  'provider duplicate-signup response must be converted to the same generic confirmation',
);
rejectMatch(
  authUi,
  /این ایمیل قبلاً ثبت شده|email has already been registered/i,
  'signup UI must not reveal that an account already exists',
);

// Raw provider messages must not become a generic last-resort UI error.
rejectMatch(
  authUi,
  /return\s+error\.message\s*;/,
  'raw Supabase Auth exception messages must not be returned to users',
);

console.log(
  'Local Auth baseline and mobile fail-closed 12-character password/recovery/provider/explicit-phone-intent/phone-linking contract are aligned. Hosted Supabase Auth configuration still requires separate live evidence.',
);
