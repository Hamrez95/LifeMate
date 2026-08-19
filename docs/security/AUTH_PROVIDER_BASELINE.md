# LifeMate Auth provider security baseline

Parent: Foundation #215.

This document separates **source/local configuration** from **hosted Supabase Auth evidence**. A local `supabase/config.toml`, green Flutter test, or Security Advisor source check must never be presented as proof of the live provider configuration.

## Source/client baseline

The repository must preserve these fail-closed properties:

- email/password remains the closed-beta primary login method;
- signup password validation requires at least 8 characters and confirmation;
- local/self-hosted Supabase Auth uses a minimum password length of at least 8;
- anonymous sign-ins are disabled;
- refresh-token rotation is enabled with an explicit bounded reuse interval;
- Google Auth and phone OTP are compile-time disabled unless a reviewed release explicitly enables them;
- password recovery remains implemented;
- duplicate-signup, invalid sign-in and password-recovery responses do not expose account existence or raw provider errors;
- no Auth provider secret is committed to source.

`tools/security/verify-auth-security-contract.mjs` and `auth-security-policy.yml` lock this repository contract.

Source-side Auth hardening is complete through #221 and #238. In particular, #238 removed the prior explicit `user already registered` account-existence response: duplicate-signup and non-session signup now converge on the same existence-neutral confirmation. Hosted provider evidence remains a separate release gate.

## Hosted production evidence required

Before #215 can close, inspect the actual project `bwdvmniywyyijjauipnh` through the Supabase Dashboard or Management API and record only non-secret configuration evidence.

Required evidence:

1. Password minimum length is at least 8 and matches the mobile wording.
2. New-user signup policy is intentional.
3. Anonymous sign-ins are disabled.
4. Email confirmation behavior is explicitly known and tested; closed-beta synthetic accounts must not require globally weakening production confirmation.
5. Recovery email flow and approved redirect/callback allowlist are tested.
6. Unused OAuth/social/phone providers are disabled by default.
7. Auth session/JWT and refresh-token settings are compatible with mobile session recovery without creating unbounded session lifetime.
8. Signup/login/refresh/recovery rate limits and provider quotas are recorded and feed the capacity/campaign preflight.
9. Leaked-password protection is enabled when available on the selected plan, or the plan limitation and compensating closed-beta decision are explicitly owned and recorded.
10. The Supabase Security Advisor is re-run after the hosted decision and no Auth P0 remains untriaged.

Supabase's official Management API exposes `GET /v1/projects/{ref}/config/auth` and `PATCH /v1/projects/{ref}/config/auth`. The current ChatGPT Supabase connector does not expose a hosted Auth-config read/mutation action, so no hosted setting should be guessed or silently changed from source code.

### Current connected-provider evidence — 2026-08-19

This is deliberately limited to facts exposed by the connected Supabase tools and official Supabase documentation:

- project `lifemate` (`bwdvmniywyyijjauipnh`) is `ACTIVE_HEALTHY` on PostgreSQL 17.6;
- the owning Supabase organization is on the `free` plan;
- the current Security Advisor Auth finding is `auth_leaked_password_protection` / `Leaked Password Protection Disabled`;
- official Supabase password-security documentation states leaked-password protection is available on **Pro Plan and above**, so this specific warning cannot be enabled on the current Free plan without a plan change;
- no source policy is weakened to silence this provider-plan warning;
- provider/redirect/email-confirmation/session/rate-limit configuration is still **not evidenced** by the current connector and remains required before #215 closure.

Do not infer provider settings from hosted defaults. Hosted defaults are documentation context, not project-specific evidence.

## Enumeration and privacy rule

Login failures must stay generic (for example, email/password incorrect). Password-reset submission must not disclose whether an account exists. Signup must not turn provider-specific duplicate-account behavior into an account-existence oracle.

The prior source finding is resolved by #238 / `40f7caa4c9b31d1a6bed687fc044f63f5e966601`: duplicate-signup and non-session signup use the same existence-neutral confirmation, while invalid sign-in and recovery remain generic. This behavior remains part of the Auth source policy and should regress closed if provider exception text changes.

## Provider-change safety

Hosted Auth settings are stateful production configuration. Change them only after:

- #210 release/control-plane ownership is protected;
- current configuration is captured as non-secret evidence;
- the rollback/forward-fix path is known;
- synthetic accounts are used for verification;
- production user sessions are not invalidated unintentionally.

No secret, access token, email address or test-account password belongs in GitHub/Trello evidence.
