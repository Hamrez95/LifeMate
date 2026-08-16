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

## Severity, owner and required action

| Severity | Closed-beta examples | Response owner | Required action |
| --- | --- | --- | --- |
| SEV-1 | suspected cross-user disclosure; authorization/consent bypass; confirmed unexplained healthcare data loss; compromised signing/release control | Founder/release operator | acknowledge immediately, pause new onboarding, stop/rollback the suspect release or activate reviewed emergency traffic controls, preserve privacy-safe evidence and keep the incident open until containment + recovery verification |
| SEV-2 | uncontrolled 5xx/timeout cascade; systemic reminder/adherence failure; database/worker failure that threatens correctness; persistent rate-limiter unsafe state | Founder/release operator | acknowledge promptly, identify exact SHA/subsystem, pause onboarding when additional state increases risk, mitigate using reviewed rollback/forward-fix/traffic controls, verify recovery and record timestamps |
| SEV-3 | warning SLO breach without correctness/security impact; bounded controlled overload; noncritical worker lag | Founder/release operator or delegated engineer | triage against the measured capacity envelope, avoid risky emergency changes, create/follow a corrective task if the warning persists |

The repository owner is the default incident response owner during the closed beta. A delegated engineer may investigate, but only the Founder/release operator may declare a production rollback/forward-fix, pause/resume new onboarding, change emergency traffic/admission controls, or authorize reopening after a SEV-1 containment event.

No incident action may disable or weaken patient/caregiver authorization, consent checks, idempotency, audit requirements, restricted database roles, signing verification or the stable-release gates.

## Closed-beta support and escalation

Security, privacy, suspected cross-user disclosure, healthcare data loss and systemic reminder/adherence reports follow one privacy-minimized path:

1. Create or link one GitHub operational incident and assign the repository owner. Do **not** paste the reporter's token, email, phone number, Account/AppUser/Person identifier, medication/treatment payload, health values or screenshots containing sensitive data.
2. Record only the report category, UTC time, affected product/surface, observed release SHA/correlation ID when already privacy-safe, and whether the issue is reproducible with synthetic/non-production data.
3. Classify SEV-1/SEV-2/SEV-3 using the table above. Any suspected cross-user disclosure, consent bypass or unexplained healthcare data loss is SEV-1 until disproven.
4. For SEV-1, pause new onboarding through `docs/operations/beta-onboarding-control.md`. Existing-user continuity is preserved unless a separate reviewed containment decision requires broader traffic restriction.
5. Diagnose using privacy-safe telemetry and aggregate database/worker evidence. Never request or move raw healthcare payloads into GitHub, Trello, chat or an external alert provider.
6. Apply only reviewed rollback/forward-fix/emergency controls. Preserve start, detection, acknowledgement, mitigation, recovery and post-verification UTC timestamps plus the exact release SHA.
7. Reopen onboarding only after the Founder/release operator confirms containment, authorization/consent invariants, restricted runtime roles and relevant synthetic smoke checks.
8. Create follow-up engineering/legal work separately when root cause, notification obligations or policy changes remain; closing the availability incident does not waive privacy/legal review.

## Synthetic routing drill

Manual dispatch supports `exercise_alert=true`. In this mode the production readiness job is skipped entirely. A separate provider-safe job creates a clearly marked `OPS DRILL` issue assigned to the same owner and then auto-closes it with the workflow run URL.

This proves GitHub Actions -> issue creation -> owner assignment -> cleanup without deliberately degrading or probing production. The drill is evidence only when the actual workflow dispatch succeeds; source code or CI policy alone does not satisfy that operational acceptance criterion.

The separate `provider-safe-incident-drill` goes further: it induces a restricted-readiness ACL failure only inside an isolated PostgreSQL service, proves detection, creates an owner-assigned privacy-minimized incident from that detected failure, exercises rollback and forward-fix paths, re-verifies restricted runtime-role invariants, and only then closes the synthetic incident.

## Response sequence

1. Acknowledge the issue and identify the exact run/SHA.
2. Follow `docs/operations/reliability-slos.md` to classify authentication, limiter, concurrency, database, application or worker/outbox pressure.
3. Do not disable authorization, consent, idempotency, audit, database-role restrictions or overload controls to make the alert disappear.
4. Pause new onboarding for unresolved security/privacy/data-loss/systemic-reminder/uncontrolled-availability incidents using `docs/operations/beta-onboarding-control.md`.
5. Use the documented rollback/forward-fix path on a provider-safe/non-production target before relying on it for a real incident.
6. Preserve start/detection/acknowledgement/mitigation/recovery timestamps and the exact release SHA in the incident evidence.

## Evidence for Foundation #216

The operational source contract is complete only when paired with actual drill evidence. Current acceptance evidence must include:

- a successful synthetic owner-routing drill;
- a provider-safe detected failure with owner assignment and privacy-minimized alert content;
- detection -> triage -> mitigation -> recovery timestamps;
- exercised rollback and forward-fix outside production user data;
- verified post-recovery security invariants;
- a no-deploy provider-independent onboarding pause/resume control with explicit operator ownership.
