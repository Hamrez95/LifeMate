# Kavenegar SMS hook — protected deployment contract

Tracking: #326, parent #271.

This runbook separates **source readiness** from **live provider activation**. Merging source does not enable Supabase Phone Auth, the Send SMS Hook, Kavenegar delivery, or the mobile `ENABLE_PHONE_OTP` flag.

## Current evidence

As recorded in #326 on 2026-08-17, the live Supabase project has an ACTIVE `lifemate-kavenegar-sms-hook` deployment, but its deployed source is not exact current `main`. The observed drift is in Kavenegar logical status `607`: the deployed hook maps it differently from current source/tests.

Do not repair that drift with an ad-hoc dashboard deploy. The approved path is the protected exact-main workflow in `.github/workflows/kavenegar-sms-hook-deploy.yml`.

## Source gate

Every relevant PR must pass:

- `deno fmt --check`;
- `deno task check`;
- `deno task test`;
- signature-boundary checks;
- privacy checks preventing sensitive hook/provider logging.

The hook must continue to:

- accept only POST;
- verify Standard Webhooks signatures, including rotation secrets;
- reject oversized or malformed payloads;
- validate OTP shape before provider delivery;
- send Kavenegar lookup requests as form-encoded POST;
- avoid logging phone numbers, OTPs, hook bodies, API keys, hook secrets, or provider response bodies;
- return privacy-safe client errors.

## Deployment gate

Deployment is manual only (`workflow_dispatch`) and uses the protected `beta` GitHub Environment. The deploy job fails closed unless all of these are true:

1. the selected ref is `refs/heads/main`;
2. checked-out `HEAD` equals `GITHUB_SHA`;
3. fetched `origin/main` equals the same SHA;
4. GitHub reports the ref as protected;
5. the repository is private;
6. the protected Environment supplies `SUPABASE_ACCESS_TOKEN`.

The workflow deploys **only** `lifemate-kavenegar-sms-hook` from that exact source SHA and explicitly preserves `--no-verify-jwt`, because the endpoint authenticates Supabase Send SMS Hook requests with Standard Webhooks signatures rather than user JWTs.

No Kavenegar API key, hook signing secret, OTP, phone number, or provider body is passed through workflow arguments or printed to the job log.

## Post-deploy safe smoke

The workflow sends a deliberately invalid Standard Webhooks signature with an empty non-sensitive body. Expected result:

- HTTP `401`;
- body reports `Invalid hook signature.`;
- provider delivery code is not reached, therefore no SMS is sent.

This smoke proves the deployed endpoint is alive and the signature boundary is still fail-closed. It does **not** prove real SMS delivery.

## Provider activation remains separate

Keep #271 open until all external/provider evidence is complete, including:

- Kavenegar credential/template ownership and restrictions;
- Supabase Send SMS Hook configuration and signing-secret rotation;
- Phone Auth/provider settings and quotas;
- real-device send/verify/resend/session behavior;
- privacy-safe operational monitoring;
- explicit decision to enable the mobile phone-OTP feature flag.

Do not enable any of those merely because this deployment workflow is merged or because its invalid-signature smoke passes.
