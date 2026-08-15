# LifeMate managed edge gateway contract

Issue: #142 / Epic #132.

Status: **source policy ready; production managed-edge/DNS enforcement not yet evidenced**.

This document defines the provider-neutral contract that a managed edge such as Cloudflare or an equivalent WAF/rate-limiting service must implement before LifeMate treats the gateway as part of the production safety boundary. It does not claim that any provider rule is currently active.

## Architecture target

```text
WellMate / CareMate
        |
        | HTTPS
        v
<custom-api-domain>
        |
        | managed DNS / TLS / WAF / outer rate limits
        v
<supabase-edge-origin>/functions/v1/lifemate-api
        |
        | application auth + distributed admission + concurrency gate
        v
restricted PostgreSQL runtime
```

The gateway is an **outer admission layer**, not an authorization layer. Supabase Auth, LifeMate patient/caregiver authorization, consent, idempotency, concurrency protection and database limits remain mandatory behind it.

The custom domain is not considered a complete security boundary while clients can trivially bypass it and call the raw origin with identical privileges. Production rollout must therefore include one of the following provider-supported controls before #142 can close:

1. origin access restricted to the managed proxy; or
2. a dedicated proxy-to-origin proof injected by the gateway and verified at the origin, with rotation and fail-closed behavior.

Do not put that proof in a mobile/web client. It is an infrastructure secret, not an API key for users.

## Canonical source policy

The machine-readable policy is:

```text
config/lifemate-edge-gateway-policy.json
```

`tools/operations/gateway_policy.ts` validates the contract and generates a provider handoff summary. CI locks the following invariants:

- rollout begins in `log` mode and moves only `log -> simulate -> block`;
- ordinary JSON payloads are capped at the same 32 KiB application limit;
- profile photos are capped at the same 3 MiB application limit and only JPEG/PNG/WebP are admitted;
- unsupported HTTP methods are rejected once enforcement is enabled;
- outer rate classes exist for probes, critical healthcare writes, sensitive writes, uploads, expensive reads, ordinary reads and ordinary writes;
- `429` is the canonical gateway rate-limit response and includes retry guidance;
- emergency protection sheds lower-priority work while the critical medication report route remains admitted to the application’s own auth/idempotency/concurrency safety layers.

The numeric outer limits in the policy are **candidate WAF ceilings**, not measured LifeMate capacity. They begin in log-only mode and must be tuned from protected staging/load evidence before block mode.

## Why critical medication reports are treated differently

`POST /api/v1/dose-occurrences/:id/report` represents the user action “مصرف کردم / skipped”. During overload, it must not be casually discarded by a blanket emergency rule.

The managed gateway should still apply provider-level DDoS/bot protections, but the LifeMate `protect_core` rule must pass this route to the application whenever the request is otherwise admissible. The application then performs:

- authentication;
- per-subject admission;
- bounded concurrency;
- idempotency;
- optimistic version checks;
- durable medication/adherence persistence.

Lower-priority aggregate reads can receive controlled `429` responses first.

## Request-size and schema boundary

The current application already enforces the canonical data contract:

- general JSON: maximum 32 KiB;
- profile photo: maximum 3 MiB plus real file-signature validation;
- route-specific bounded text/UUID/date/time/schedule validation;
- unknown routes return application 404.

The gateway should enforce method/path/content-type/body-size rules that can be kept exactly aligned with source. It should **not** invent a second independent medical JSON schema that can drift from the reviewed application validators.

A complete OpenAPI description for every Edge route is not currently the canonical source of truth. If one is introduced later, provider schema validation may be generated from that reviewed spec and staged in log-only mode before blocking.

## Privacy-safe gateway logging

Managed-edge logs are operational metadata, not a healthcare datastore. Do not enable request-body capture or Authorization-header capture.

At minimum, retain only fields needed for abuse/capacity diagnosis, for example:

- timestamp;
- provider rule ID/action;
- HTTP method;
- normalized path without query-string values;
- response status;
- request size bucket;
- coarse bot/ASN/country signal if operationally required;
- provider request/ray identifier.

Do not place JWTs, cookies, raw query strings, email/phone, Person/Account IDs, medication names, health observations or menstrual data in gateway rule labels/log payloads.

Retention for provider logs must be explicitly configured and documented before production enforcement.

## Staged rollout

### Stage 0 — source contract

Required evidence:

- gateway policy CI green;
- application body-size invariants green;
- Scale-01 staging harness available;
- emergency policy tests prove critical medication writes are not shadowed by generic rules.

### Stage 1 — DNS/proxy in log mode

Configure the chosen provider and custom API domain, but start LifeMate-specific rules as observe/log-only for at least the policy’s minimum observation window.

Verify:

- TLS and DNS resolution;
- exact origin routing;
- no Authorization/body logging;
- no false-positive block for WellMate/CareMate patient/caregiver journeys;
- raw origin bypass protection design is ready;
- provider metrics distinguish rule matches from origin 429/503.

### Stage 2 — simulate

Apply the intended decisions in simulation/count mode. Run protected staging capacity profiles and compare:

- would-block counts;
- application 429/503;
- p50/p95/p99;
- dropped iterations;
- DB connections/waits;
- Redis/admission health;
- critical idempotency replay results.

Tune only with evidence. Do not weaken the application limiter to compensate for a bad WAF rule.

### Stage 3 — block

Enable method, size and tuned rate controls. Acceptance requires a test that produces the expected gateway `429` with retry guidance and another test proving an ordinary critical medication report reaches the application.

### Stage 4 — origin bypass closed

Prove that directly targeting the raw origin cannot bypass the managed gateway’s intended safety boundary. Only after this evidence may the gateway be called production-enforced.

## Emergency `protect_core` runbook

Use only when there is a real overload/abuse event and normal controls are insufficient.

1. Record incident start time and current release SHA.
2. Confirm the problem is ingress pressure, not a broken database migration/auth provider/dependency.
3. Enable the reviewed `protect_core` policy, not a blanket “block all”.
4. Verify the medication report route still reaches the application and preserves idempotency.
5. Verify expensive/ordinary work receives bounded `429` rather than hanging connections.
6. Watch application 429/503, DB connections/waits, queue lag and critical-write failures.
7. If the gateway rule worsens critical traffic, roll it back immediately to the previous staged ruleset.
8. After traffic normalizes, disable emergency mode and capture the incident/rule evidence before changing thresholds.

Do not use emergency mode to hide a persistent capacity defect. A repeated overload pattern belongs in Scale-01/02/04 tuning.

## Rollback

The provider rollout must keep a known-good prior ruleset. Rollback means reverting the LifeMate-specific WAF/rate-limit rules to the previous staged configuration while keeping TLS/DNS intact.

Never “fix” an incident by:

- disabling Supabase/LifeMate authentication;
- disabling idempotency;
- making database roles privileged;
- removing request-size checks;
- switching off all application rate/concurrency protection;
- exposing direct database credentials to the client.

## Evidence required to close #142

Repository/source evidence alone is insufficient. Closure requires provider-side proof of:

- chosen custom API domain and DNS/proxy architecture;
- provider-managed rules corresponding to the reviewed policy SHA;
- log -> simulate -> block rollout evidence;
- tested gateway 429 and request-size behavior;
- critical medication route survival under emergency mode;
- privacy-safe logging configuration and retention;
- origin-bypass mitigation;
- emergency rollback test/runbook ownership.

Until those exist, report the gateway as **source-ready / production-external-blocked**, not Done.
