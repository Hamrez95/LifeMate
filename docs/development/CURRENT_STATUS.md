# Current development status

Last updated: 2026-08-15

This file is a concise engineering handoff. GitHub issues are the canonical backlog. For the active shared foundation closure, use **#170**. Do not infer that an unchecked live/provider/device gate passed because its source implementation exists.

## Current closed-beta architecture

```text
WellMate / CareMate
        ↓ Supabase Auth + HTTPS
Supabase Edge Function: lifemate-api
        ↓ restricted server-only PostgreSQL connection
PostgreSQL schemas: identity / consent / lifemate / related canonical schemas
```

`backend-dotnet` remains the canonical domain/schema and EF reference. It is not a second deployed healthcare API runtime.

Identity is intentionally separated:

```text
Account → AccountPersonLink → Person
           ↑
     legacy AppUser bridge
```

Account UUID, AppUser UUID and Person UUID must never be assumed to be equal.

## Verified source/runtime foundation

### Identity, consent, privacy and lifecycle

- Account/AppUser/Person mapping-aware identity bridge and compatibility resolvers are merged.
- retention-v2 account deletion is merged and its production database migrations were applied.
- authenticated self-service portable export and deletion lifecycle have automated cross-user/caregiver isolation coverage.
- the export/deletion product wording is locked to the runtime contract by CI; jurisdiction-specific legal/privacy approval remains a human launch gate.
- privacy-safe crash/error reporting is merged for Flutter, Edge and .NET; raw exception messages/health payloads are not accepted as crash telemetry contracts.

### Reliability

- durable mobile mutation queue and reconnect/expired-session/outage automation are on `main`.
- retryable healthcare writes retain idempotency boundaries; medication adherence replay is covered.
- exact physical reminder behavior after permission denial/recovery, reboot, timezone change, app update and OEM battery restrictions still requires real-device evidence.
- a weekly logical PostgreSQL restore drill uses independent PostgreSQL 17.6 source/restore clusters and verifies restored schema, RLS, restricted role boundaries and synthetic healthcare access. This does not prove provider-managed production backup/PITR availability.

### Database and overload protection

- each Edge isolate deliberately uses at most one postgres.js connection.
- statement/lock/idle-in-transaction timeouts are bounded.
- free disposable PostgreSQL 17.6 + actual Deno `lifemate-api` smoke is part of CI.
- free actual-runtime smoke evidence has shown 60/60 2xx responses, no 4xx/5xx/429/503, no dropped iterations and peak restricted runtime DB connections of one. This is local regression evidence, **not a hosted RPS capacity claim**.
- a real local PostgreSQL lock-pressure fault test proves the restricted API hits its approximately 2-second lock timeout, returns controlled `503 database_busy` with `Retry-After: 2`, observes a waiting runtime connection and recovers to 200 after the lock is released.
- Scale-01 k6 tooling hard-blocks the production project and has bounded smoke/read/ramp/spike/soak/care/write/retry profiles, identity-pool requirements, pressure collection and machine-readable p50/p95/p99/max evidence.
- the application supports an atomic shared Redis/Upstash admission store with conservative fail-safe fallback and multi-instance tests. Production shared Redis is **not yet evidenced**.
- source/release readiness requires transaction-pooler semantics for the stable release. Production Supavisor transaction pooling is **not yet evidenced**.

### Managed edge / WAF

A provider-neutral Scale-10 source contract is merged:

- staged `log → simulate → block` rollout;
- deterministic provider-trusted source-IP outer counters;
- request method/body/media bounds aligned with the application;
- sensitive data-export classification;
- controlled 429 behavior;
- `protect_core` emergency mode that preserves critical medication/adherence writes for application auth/idempotency/concurrency checks;
- privacy-safe logging and rollback/origin-bypass requirements.

No real custom API domain/DNS/WAF/origin-bypass enforcement is currently claimed. #142 remains open.

## Supabase production baseline

- Project: `lifemate`
- Ref: `bwdvmniywyyijjauipnh`
- Region: `eu-west-1`
- retention-v2 identity/privacy migrations are live.
- previously measured PostgreSQL `max_connections`: approximately 60.
- database role budget previously verified: Edge runtime cap 20; worker cap 5.
- Security Advisor rechecked 2026-08-15: remaining warning is Supabase Auth leaked-password protection disabled.
- Performance Advisor rechecked 2026-08-15: INFO-only unused-index notices on the currently low-traffic database; indexes are not removed merely to silence the advisor.

Production source/config must be re-verified immediately before a stable release; this handoff is not an immutable production attestation.

## Release engineering state

- founder-owned `SUPABASE_ACCESS_TOKEN` is usable by GitHub Actions/Supabase CLI.
- exact-main Edge deployment is separated from stable Android artifact generation.
- the final stable Android `verify-and-build` job is manual-only and source-bound to GitHub Environment `beta`.
- stable signing remains fail-closed; no debug-signing fallback is accepted.
- stable release readiness requires the restricted transaction-pooler readiness response, authenticated telemetry smoke and exact deployed SHA before APK build.
- final artifacts are designed to record APK SHA-256, signing certificate SHA-256 and APK-derived Android SDK metadata.

### Important live GitHub Environment blocker

The repository has an Environment named `beta`, but the live GitHub API check on 2026-08-15 reported:

- no protection rules;
- no deployment branch policy.

Therefore `beta` is **not yet treated as a protected release Environment**. The integration also cannot enumerate Environment secret names, so dedicated beta identities/signing/environment-only secret presence must not be guessed.

## Free/local evidence completed during Foundation Closure

- #175 — retention-v2 account deletion / mapping-aware identity fixes.
- #179 — privacy-safe crash/error telemetry.
- #180/#181 — exact-main Edge deployment separated from stable artifact build.
- #182 — distributed rate-limit source hardening.
- #183 — DB connection/query/pooler source/release hardening.
- #184/#187 — repeatable capacity harness + identity/pressure evidence hardening.
- #185 — managed gateway/WAF source contract.
- #188 — actual local API/PostgreSQL/Auth/k6 smoke.
- #190 — PostgreSQL lock-pressure controlled-503/recovery fault smoke.
- #191 — required real p50/p95/p99/max capacity artifact metrics.
- #192 — self-service privacy lifecycle wording/runtime drift gate.
- #193 — stable Android job bound to GitHub Environment `beta`.

## Foundation gates that remain open

These must stay explicit rather than being simulated as passed:

1. **Hosted capacity / Scale-01 (#133)** — run protected non-production hosted load and identify the first hosted bottleneck; the Epic's 60+ minute soak also needs safe session rotation or equivalent evidence.
2. **Shared production admission / Scale-02 (#134)** — provision and prove the shared Redis runtime configuration.
3. **Production DB transport / Scale-04 (#136)** — prove Supavisor transaction-pooler routing and the production connection budget.
4. **Managed gateway / Scale-10 (#142)** — real custom domain/DNS/WAF rules, privacy-safe provider logging and origin-bypass mitigation.
5. **Protected release Environment** — configure actual `beta` Environment protection/deployment policy and verify the required beta-scoped credentials/identities/signing material.
6. **Live three-account smoke** — dedicated synthetic patient, caregiver and unrelated accounts; live cross-user/revocation evidence.
7. **Physical Android QA** — release-signed install plus reminder permission/reboot/timezone/update, offline/reconnect, RTL/LTR, text scaling/accessibility and representative-device checks.
8. **Provider backup evidence** — logical restore drill is green, but provider-managed production backup/PITR evidence remains separate.
9. **Supabase Auth leaked-password setting** — remaining Security Advisor configuration decision.
10. **Jurisdiction-specific privacy/legal review** — not replaced by technical contract tests.
11. **Final exact-main release** — only after every applicable gate above has evidence: deploy final SHA, live smoke, build signed WellMate/CareMate, record hashes/cert/SDK metadata, complete device QA, then create the stable invite-only tag/release.

## Safety rules for further work

- Never run high-load k6 profiles against production.
- Never weaken Auth, consent, RLS, idempotency, rate/concurrency controls, DB role restrictions, query timeouts or release signing to make a gate green.
- Redis is admission/cache infrastructure, never the source of truth for treatment/adherence.
- Do not add sensitive PHI/PII to logs, telemetry, load-test artifacts or GitHub/Trello evidence.
- Do not call a local/CI result a production capacity claim.
- Do not call the beta stable until Foundation #170 and its external/human release gates are actually evidenced.
