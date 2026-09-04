# CocoonMate pregnancy API contract — v1

Status: Phase 0 frozen contract for CocoonMate issue #780.

## Boundaries

- Mobile Cocoon code calls `lifemate-api` through the shared `lifemate_client` package. It does not query pregnancy, medication, treatment, observation or care-event tables directly.
- The authenticated Account is resolved server-side. The server resolves the caller's active Self Person; client identifiers are never authorization proof.
- Pregnancy health authorization is evaluated independently from relationships and Commerce. `enrollmentState` and `entitlementState` are intentionally separate values.
- A pregnancy episode belongs to the mother's Person. Gestational age is derived from canonical dating inputs; there is no mutable `current_week` truth.

## Versioning

Every Cocoon pregnancy envelope contains `contractVersion: 1`. Clients must ignore unknown response fields and tolerate missing optional fields. Removing/renaming a v1 field or changing its meaning requires a versioned endpoint/contract rather than an in-place breaking change.

## Owner endpoints

All routes require authenticated LifeMate identity and canonical Person resolution.

| Method | Route | Authorization | Purpose |
| --- | --- | --- | --- |
| GET | `/api/v1/cocoon/bootstrap?asOfDate=YYYY-MM-DD` | `pregnancy.summary.read` | Person, enrollment, separate Commerce reference, active episode and runtime/cache rules |
| GET | `/api/v1/cocoon/pregnancy/snapshot?asOfDate=YYYY-MM-DD` | `pregnancy.summary.read` | Home/bootstrap pregnancy read model |
| GET | `/api/v1/cocoon/pregnancy/episodes` | `pregnancy.summary.read` | Owner pregnancy history |
| POST | `/api/v1/cocoon/pregnancy/episodes` | `pregnancy.owner.manage` | Idempotent draft/active episode creation |
| POST | `/api/v1/cocoon/pregnancy/episodes/{id}/activate` | `pregnancy.owner.manage` | Idempotent draft activation with expected version |
| PATCH | `/api/v1/cocoon/pregnancy/episodes/{id}/dating` | `pregnancy.owner.manage` | Idempotent dating revision with provenance + expected version |
| POST | `/api/v1/cocoon/pregnancy/episodes/{id}/end` | `pregnancy.owner.manage` | Idempotent lifecycle end/outcome transition |

The snapshot is a read model, not a duplicate persistence model. Today's actions will be projected from canonical `care_events`; medication/treatment references remain canonical `medications` / `treatment_plans`; observations remain canonical `health_observations`.

## Enrollment versus entitlement

`enrollmentState` describes pregnancy health lifecycle only: `not_enrolled`, `draft`, `active`, or `ended`.

`entitlementState.state` describes the latest Cocoon Commerce state only: `active`, `inactive`, or `unknown`. `unknown` is fail-closed for paid activation and must not be interpreted as active. An entitlement never grants pregnancy health access and an active pregnancy never fabricates a paid entitlement.

## Idempotency and concurrency

Every POST/PATCH API mutation under `/api/v1/` is protected by the shared mutation coordinator. The `Idempotency-Key` is bound to authenticated actor, HTTP method + route, and request-body hash. Keys are retained for 24 hours. Reuse with a different body returns `idempotency_key_reused`; in-flight duplicates return `idempotency_in_progress`; completed duplicates replay the original 2xx response.

Pregnancy storage provides a second domain-level guard. Episode creation serializes per mother Person with a transaction-scoped advisory lock and stores a hashed creation key. Activation, dating revision and end transitions store hashed event/revision keys and use optimistic `expectedVersion`. Concurrent requests therefore cannot create two active episodes or silently overwrite dating/lifecycle state.

A key replay by another authenticated Account does not share the global idempotency record because actor identity is part of the key namespace. Pregnancy authorization still runs against the resolved Account/Person context.

## Error contract

Transport errors expose stable codes and safe messages only. Raw PostgreSQL/provider details are never returned.

- `400`: validation/idempotency/dating input error.
- `401`: authentication/session missing.
- `403 pregnancy_access_denied`: pregnancy scope/consent authorization failed.
- `404 pregnancy_not_found`: resource not present in the authorized Person context.
- `409`: `active_pregnancy_exists`, `pregnancy_version_conflict`, invalid lifecycle transition, or idempotency conflict.
- `503`: authoritative database/idempotency/Commerce dependency temporarily unavailable.
- `500 pregnancy_operation_failed`: unexpected pregnancy-domain failure with no provider detail.

UI localization belongs to presentation code. Transport models contain machine codes and neutral safe messages only.

## Owner versus shared/caregiver read models

The v1 routes above are owner-context routes. A future partner/caregiver endpoint must not reuse owner bootstrap semantics. It must resolve an explicit subject Person + episode, require the exact delegated pregnancy scope and active `pregnancy_sharing` consent, and return a scope-shaped read model. `pregnancy.owner.manage` is never delegated.

Shared/caregiver responses must not expose owner-only history or fields merely because a relationship exists. Revocation, expiry or episode end removes shared authorization immediately at the server.

## Offline/cache contract

- Owner last-known pregnancy snapshot and deterministic dating inputs may be cached durably for offline presentation. Cached data must be visibly last-known and never represented as freshly server-confirmed.
- Shared/caregiver pregnancy data is not an authority-cache: when online authorization cannot be confirmed, the app must not expose newly requested shared data from stale authorization.
- Episode create/activation, dating revision, lifecycle end/outcome and access-grant changes require authoritative online confirmation. They are not background-queued as if confirmed.
- Future low-risk owner check-ins may use the shared durable outbox only after their endpoint defines replay/conflict semantics. `queued` and `server_confirmed` are distinct UI states.
- Entitlement verification and first paid activation require online authoritative Commerce state. Cached entitlement state cannot unlock paid functionality.
- Local owner reminders/calendar execution may continue from durable canonical-downloaded data and OS scheduling; it does not depend on FCM or daily connectivity.

## Privacy-safe observability

Allowed operational fields: correlation/request ID, product/app/version/environment, normalized route, result/error class, status and latency.

Ordinary telemetry must not include LMP, EDD, gestational week tied to identity, pregnancy loss/outcome, symptom/notes text, measurements, document names, medication names or raw Person/Episode IDs. Shared Dart pregnancy DTOs redact reproductive dates and identifiers from `toString` diagnostics.

## Extension rules

Future check-ins, symptoms, observation links, appointment links, sharing and timeline endpoints use the same authenticated Account → authorized Person pattern, shared idempotency coordinator for mutations, typed shared-client DTOs, stable safe error mapping, and explicit offline status semantics. They must reference canonical domain records rather than creating a parallel Cocoon database/scheduler/outbox architecture.
