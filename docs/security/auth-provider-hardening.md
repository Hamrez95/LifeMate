# LifeMate closed-beta Auth provider hardening

Parent tracking issue: #215.

This document records the provider-side controls that must be independently
verified before LifeMate Auth is considered production-hardened. Source code
passing CI is not evidence that hosted Supabase Auth settings are aligned.

## Verified source posture

- Email/password remains available.
- Phone OTP is fail-closed by default behind `ENABLE_PHONE_OTP=false`.
- Google auth is fail-closed by default behind `ENABLE_GOOGLE_AUTH=false`.
- Phone sign-in uses canonical Iranian E.164 numbers and returning sign-in does
  not create a new user implicitly.
- Signup and password recovery must use `LifeMatePasswordPolicy` for newly
  created passwords. Existing password sign-in is not subject to the stronger
  client-side creation policy.
- Recovery UI must never render raw `AuthException.message` provider details.
- Password-reset responses must remain non-enumerating.

## Intended closed-beta password policy

Configure hosted Supabase Auth to enforce the same or stronger policy as the
client:

- minimum length: 12 characters;
- at least one lowercase letter;
- at least one uppercase letter;
- at least one digit;
- at least one symbol.

The client policy is defense in depth and UX guidance. It is not a replacement
for provider enforcement because alternate clients can call Auth directly.

## Live provider checklist

Before closing #215, capture dated evidence for every item below.

### Password breach protection

- Enable leaked-password protection when the active Supabase plan supports it.
- If the plan does not support it, record the plan limitation, compensating
  controls, owner decision, and the upgrade condition.
- Re-run the Supabase Security Advisor after the change.

Observed on 2026-08-17: the Security Advisor reports
`auth_leaked_password_protection` as WARN / disabled. This document does not
claim that setting has been changed.

### Email confirmation and recovery

- Verify email confirmation behavior matches the closed-beta onboarding flow.
- Verify recovery is enabled and uses only approved redirect targets.
- Keep recovery responses generic so account existence is not disclosed.
- Configure production SMTP before relying on email delivery at scale.

### Redirect and callback allowlist

Allow only the application callbacks and required production web callbacks.
The mobile source currently expects:

- `wellmate://auth/callback`
- `caremate://auth/callback`

Remove stale localhost, preview, or unused callback entries before production.

### Auth providers

- Keep Google disabled until its separate provider evidence is complete.
- Keep phone OTP disabled until #271 provider/delivery evidence is complete.
- Disable any OAuth/provider integration not intentionally used by LifeMate.

### Abuse controls and rate limits

Verify the live Auth rate-limit configuration rather than assuming Supabase
defaults. At minimum review and record:

- OTP send and resend limits;
- OTP verification limits;
- password/email auth limits;
- token refresh limits;
- recovery email limits;
- any CAPTCHA/bot-protection configuration used for public exposure.

Mobile clients must show generic retry guidance and must not expose provider
quota details, phone numbers, OTP values, tokens, or secrets in logs.

### OTP lifetime

When phone OTP is activated, verify the hosted OTP expiry is intentionally
bounded for the LifeMate risk model and not left at an unexpectedly long
value. The provider setting is authoritative; client timers are only UX.

### Sessions and refresh tokens

Record the live values for:

- access-token lifetime;
- refresh-token rotation/reuse detection;
- inactivity timeout, if the plan supports it;
- absolute session lifetime, if the plan supports it;
- single-session policy, if intentionally enabled.

Do not shorten sessions solely in the client and call the provider hardened.
Provider settings and mobile behavior must be reviewed together to avoid
unexpected logout or unsafe token persistence.

## Closure evidence required for #215

#215 remains open until all of the following exist:

1. dated live Supabase Auth settings evidence;
2. Security Advisor rerun with each finding resolved or explicitly accepted;
3. provider policy equal to or stronger than `LifeMatePasswordPolicy`;
4. redirect/provider allowlist evidence;
5. rate-limit/abuse-control evidence;
6. session/token configuration evidence;
7. successful mobile auth regression tests for email/password, recovery, and
   every provider intentionally enabled for the beta.

Secrets, OTP values, provider credentials, and full contact identifiers must
never be added to this runbook or CI artifacts.
