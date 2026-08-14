# LifeMate viral campaign preflight and emergency runbook

No high-traffic campaign is approved from intuition, follower count, marketing urgency or a previously green release. A campaign is allowed to proceed only when the manual `viral-campaign-preflight` workflow returns **GREEN** for the exact deployed commit using non-sensitive evidence measured within the previous 7 days.

`YELLOW` means do not launch at the planned traffic level without an explicit capacity reduction or a new measured run. `RED` is a hard no-go.

## Evidence workflow

1. Deploy the exact candidate release to the protected staging environment.
2. Run the approved k6 mix and database-pressure collector. Use synthetic accounts only.
3. Record the exact release commit and the current campaign traffic assumption.
4. Verify current Supabase Auth/database/Edge quotas and provider usage/budget alerts.
5. Verify distributed admission control, worker health, observability, lightweight readiness, gateway controls and rollback.
6. Commit a **non-sensitive** evidence JSON under `docs/operations/evidence/`. Do not include URLs with credentials, tokens, user identifiers, health payloads, database connection strings or Redis secrets.
7. Run `.github/workflows/viral-campaign-preflight.yml` manually with that evidence path.
8. Store the generated `viral-campaign-preflight-result` artifact with the campaign approval record.

The validator compares **measured capacity to the planned campaign demand plus the declared safety factor**. It does not assume that a previous target such as 500 RPS is sufficient for every campaign.

## Mandatory input evidence

The JSON schema is represented by `ViralPreflightEvidence` in `tools/operations/viral_preflight.ts`. Required evidence includes:

- exact source release commit and exact deployed release commit;
- expected sustained RPS, peak RPS and peak duration for the campaign;
- safety factor between 1.1x and 3x;
- recent sustained/spike/soak measurements with p95/p99 and uncontrolled 5xx rate;
- duplicate/lost critical-write count and post-overload recovery result;
- database max/peak connections, pooler enforcement and query timeouts;
- distributed admission-control state and outage-fallback test;
- current Auth quota review for the planned signup/login burst;
- outbox lag and unexplained dead-letter count;
- observability/alert state;
- lightweight readiness + deep deployment verification result;
- managed edge gateway rollout and emergency-rule test;
- rollback test;
- provider budget/usage alerts.

## Green / Yellow / Red rules

### RED — launch blocked

Any of the following blocks the campaign:

- capacity report older than 7 days or for a different release;
- measured sustained/peak capacity below campaign demand × safety factor;
- spike test shorter than the planned peak duration;
- p95 > 1500 ms or p99 > 3000 ms;
- uncontrolled 5xx >= 0.5%;
- any duplicate or lost critical write;
- no demonstrated recovery after overload;
- serverless transaction pooler not enforced;
- database peak connections >= 85% of configured max or any query timeout in the capacity run;
- distributed admission control missing/unhealthy or outage fallback untested;
- Auth quota/burst assumptions unverified;
- outbox oldest-ready age >= 15 minutes or unexplained dead letters;
- required telemetry/alerts missing;
- readiness/deep verification incomplete;
- managed edge gateway, staged log-to-block rollout or emergency rule missing;
- rollback untested;
- budget/usage alerts missing.

### YELLOW — reduce plan or re-measure

Yellow is used only when there is no red finding, for conditions such as:

- p95 > 1200 ms or p99 > 2400 ms while still inside SLO;
- database peak connection usage between 70% and 85%;
- outbox oldest-ready age between 2 and 15 minutes;
- short sustained/soak evidence (less than 10 minutes sustained or 30 minutes soak).

### GREEN — campaign can enter final business approval

Green means all technical hard gates pass for the exact release and the measured system has enough headroom for the declared campaign. It is not permission to bypass normal product, legal, privacy or business approvals.

## Emergency actions by limiting subsystem

### 429 growth / admission-control saturation

- Confirm Redis/shared limiter health and current request class before changing thresholds.
- If traffic is expected and database pressure is low, reduce noncritical campaign traffic first; do not immediately raise every route limit.
- Keep critical treatment/adherence classes protected.
- Never disable distributed rate limiting as an emergency shortcut.

### Redis/shared limiter outage

- Keep conservative local fallback active.
- Reduce external campaign traffic and optional reads.
- Do not fail open to unlimited traffic.
- Restore/replace the shared limiter, then verify telemetry health before increasing traffic.

### Database connection or query pressure

- Do not increase Edge concurrency while DB connection ratio or waits are elevated.
- Activate gateway/emergency rules for noncritical routes.
- Inspect measured hot routes/query plans and pooler state.
- Preserve critical write and authorization/consent/audit paths.

### Supabase Auth throttling

- Pause acquisition/signup-driving traffic before changing API limits.
- Keep existing authenticated healthcare traffic separate from signup recovery actions where possible.
- Reconcile planned signup burst with current provider quota before resuming.

### Worker/outbox lag

- Keep authoritative healthcare writes transactional; do not redirect them to an unsafe best-effort queue.
- Use `docs/operations/outbox-worker.md` to identify dependency failure/dead letters.
- Do not bulk requeue unknown dead letters.
- Reduce optional event producers if backlog continues to grow.

### Edge gateway / bot / volumetric event

- Move the pre-tested emergency rule from staged/log mode to blocking for noncritical traffic.
- Preserve the core authenticated healthcare flow and application-level authorization/rate limiting.
- Record exact rule changes and rollback time.

### Uncontrolled 5xx or timeout cascade

- Stop campaign traffic growth.
- Correlate the failure window using release version, correlation IDs, API latency/status telemetry, DB pressure and worker lag.
- Roll back to the last known healthy exact release if the regression follows deployment.
- Do not repair production data speculatively during an overload event.

## Recovery criteria

Traffic can be restored gradually only after:

- the limiting subsystem is healthy;
- 5xx/timeouts return below SLO thresholds;
- database connection/wait pressure has recovered;
- distributed admission control is healthy;
- queue lag is stable or falling with no unexplained critical dead letters;
- lightweight readiness is green;
- a short controlled verification ramp succeeds.

After the incident/campaign, record peak RPS, p95/p99, controlled overload rate, DB peak/max ratio, queue lag, limiter state, cost/usage impact, any emergency changes and the resulting capacity-envelope update. Never include health payloads or user identifiers in the incident record.
