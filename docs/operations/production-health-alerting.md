# Production readiness alert routing

Parent: Foundation #216.

## Live baseline

`production-health-monitor` runs the lightweight `lifemate-readiness` probe every 15 minutes. A failed probe opens or updates one deduplicated GitHub issue titled `OPS ALERT — Production readiness failed` and assigns it to the repository owner. The next successful probe records the recovery run and closes that incident.

GitHub issues are the zero-additional-cost closed-beta alert destination for this gate. A future paging provider may supplement this path, but it must not remove the privacy and ownership guarantees below.

## Privacy boundary

The alert contains only:

- failure kind;
- workflow/run URL;
- source SHA;
- UTC detection time;
- response owner.

It does not copy the readiness response body, tokens, emails, phone numbers, Account/AppUser/Person identifiers or healthcare payloads into the incident. Detailed diagnosis stays in privacy-safe telemetry and aggregate infrastructure evidence.

## Synthetic routing drill

Manual dispatch supports `exercise_alert=true`. In this mode the production readiness job is skipped entirely. A separate provider-safe job creates a clearly marked `OPS DRILL` issue assigned to the same owner and then auto-closes it with the workflow run URL.

This proves GitHub Actions -> issue creation -> owner assignment -> cleanup without deliberately degrading or probing production. The drill is evidence only when the actual workflow dispatch succeeds; source code or CI policy alone does not satisfy that operational acceptance criterion.

## Response sequence

1. Acknowledge the issue and identify the exact run/SHA.
2. Follow `docs/operations/reliability-slos.md` to classify authentication, limiter, concurrency, database, application or worker/outbox pressure.
3. Do not disable authorization, consent, idempotency, audit, database-role restrictions or overload controls to make the alert disappear.
4. Pause new onboarding for unresolved security/privacy/data-loss/systemic-reminder/uncontrolled-availability incidents.
5. Use the documented rollback/forward-fix path on a provider-safe/non-production target before relying on it for a real incident.
6. Preserve start/detection/mitigation/recovery timestamps in the incident evidence.

## Remaining #216 evidence

Source alert routing and SLO/runbook contracts are not the whole gate. #216 remains open until:

- the synthetic routing drill is actually dispatched and reaches the intended owner;
- a provider-safe failure/incident exercise records detection -> triage -> mitigation -> recovery;
- rollback or forward-fix is exercised outside production user data;
- onboarding pause/emergency ownership is explicitly evidenced.
