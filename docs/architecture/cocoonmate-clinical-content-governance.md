# CocoonMate clinical content and safety governance

CocoonMate clinical content is repository-versioned, deterministic and review-gated. Flutter presentation code must consume approved content/rule contracts rather than hardcoding clinically meaningful pregnancy guidance inside screens.

## Content classes

The V1 contract separates weekly education, routine self-care, appointment/test information, red-flag safety guidance, and legal/emergency wording. Each content unit has a stable key, integer version, locale, jurisdiction, publication state, severity/classification, review metadata and source references.

A published unit is usable only while its review window remains valid. Disabled, draft or review-expired content is never selected as current guidance. Missing locale/week content falls back to an approved bundled fallback; the renderer must not invent replacement medical text.

## Weekly mapping

Weekly content is selected from the canonical derived gestational week. `current_week` is not persisted by the clinical content system. Week selection supports the bounded pregnancy range and uses a stable content key/version so the client can cache the last approved unit for offline presentation.

The first repository-backed bundle is intentionally small: it proves the version/review/fallback contract before Home and Week Detail add the reviewed production content set. Adding or replacing content does not require a database schema migration.

## Safety rule boundary

Red-flag evaluation is a bounded deterministic rule engine. Inputs are typed categories; outputs are approved escalation classes and guidance keys, never diagnoses.

The following rules are mandatory:

- no LLM/free-form model determines emergency escalation;
- relationship, entitlement, enrollment or user role never changes clinical rule severity;
- unsupported/ambiguous input uses conservative approved fallback guidance;
- disabled or review-expired rule sets also fall back conservatively rather than silently disappearing;
- AI may later explain an already-approved outcome, but may not override it.

The V1 rule set only establishes the governance/runtime boundary. Expansion of symptom categories or thresholds requires clinical review, version increment, fixtures and review metadata before publication.

## Authoring and publication lifecycle

1. **Author** — create/update a stable content key or rule-set version in a dedicated Cocoon clinical-content change.
2. **Clinical review** — record a non-PHI reviewer reference, reviewed-at date, review-due date and source/reference metadata.
3. **Test** — add deterministic fixtures for affected week/locale/rule boundaries, expired/disabled behavior and conservative fallback.
4. **Publish** — mark the reviewed unit/rule set `published` only in the reviewed change. Ordinary Command Center operators do not directly publish high-risk safety rules.
5. **Observe safely** — telemetry may record content/rule version and coarse outcome class when approved, but not raw symptom text, LMP, EDD, gestational week tied to identity, measurements, notes or document names.
6. **Rollback** — disable the unsafe version and restore a previously reviewed version or approved bundled fallback. Rollback must not depend on an LLM or client-side ad-hoc text.
7. **Review/expiry** — before `reviewDueAtUtc`, renew review metadata or publish a new version. Expired content/rules fail to the approved fallback contract.

## Offline and service failure

Approved bundled content and rules are part of the durable local execution surface. Remote content availability is not required to display the safe fallback. Cached owner content may be presented under the product's offline policy, but stale shared authorization is never evidence that another account is still allowed to see pregnancy PHI.

If a remote content service is introduced later, it must validate signed/versioned metadata before activation and preserve the bundled safe fallback. A remote fetch failure must not remove emergency/safety UX.

## Privacy and administration

Clinical metadata contains no user PHI. Ordinary analytics must not carry raw safety inputs or symptom text. Command Center work for #263 may manage governed publish/rollback/version metadata with RBAC/AAL2/audit, but it must not become an unrestricted clinical-rule editor.

## Test evidence required for each change

- gestational week boundary/mapping fixtures;
- Persian/English locale/fallback fixtures where content changes;
- disabled and expired behavior;
- deterministic safety-rule fixtures;
- unsupported input fallback;
- evidence that no model/LLM is in the escalation decision path;
- privacy-safe diagnostics/telemetry contract checks.
