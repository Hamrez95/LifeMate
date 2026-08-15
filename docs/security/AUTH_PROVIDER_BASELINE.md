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
- raw provider exceptions are not used as a generic user-facing error response;
- no Auth provider secret is committed to source.

`tools/security/verify-auth-security-contract.mjs` and `auth-security-policy.yml` lock this repository contract.

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

Supabase's official Management API exposes `GET /v1/projects/{ref}/config/auth` and `PATCH /v1/projects/{ref}/config/auth`. The current ChatGPT Supabase connector does not expose a hosted Auth-config mutation action, so no hosted setting should be guessed or silently changed from source code.

## Enumeration and privacy rule

Login failures must stay generic (for example, email/password incorrect). Password-reset submission should not disclose whether an account exists. Signup behavior must also be reviewed so a provider-specific `user already registered` response is not unnecessarily turned into an account-existence oracle in the application UI.

At the time this baseline was introduced, the shared Flutter Auth UI still contains a specific `user already registered` friendly mapping. That is a source finding under #215 and must be removed or explicitly justified/tested before the Auth source portion is considered complete.

## Provider-change safety

Hosted Auth settings are stateful production configuration. Change them only after:

- #210 release/control-plane ownership is protected;
- current configuration is captured as non-secret evidence;
- the rollback/forward-fix path is known;
- synthetic accounts are used for verification;
- production user sessions are not invalidated unintentionally.

No secret, access token, email address or test-account password belongs in GitHub/Trello evidence.
