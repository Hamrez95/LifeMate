# Privacy-safe product telemetry

Parent: #263 / #53 / #759.

## Purpose

LifeMate product analytics measures coarse activation, activity and reliability funnels without turning telemetry into a second copy of health or identity data. The telemetry endpoint is authenticated. For persisted product activity, the authenticated subject is resolved **server-side** to the canonical LifeMate account; the client never sends an account/person identifier and the auth subject is never stored as the analytics identity.

Crash telemetry remains a separate backwards-compatible envelope. Product events are accepted only when `kind=product` and every field matches this document and the server parser.

## Approved product events

Only these fixed event names are permitted:

- `app_opened`
- `auth_login_succeeded`
- `auth_session_restored`
- `onboarding_started`
- `onboarding_completed`
- `care_pairing_started`
- `care_pairing_completed`
- `care_access_revoked`
- `offline_queue_enqueued`
- `offline_queue_recovered`

The pre-persistence client wire name `app_open` is accepted only as a compatibility alias at the ingestion parser and is normalized to canonical `app_opened` before persistence. New clients emit `app_opened` directly.

Adding an event requires a reviewed source change to the server allowlist, shared client enum and event taxonomy/definition. Runtime code cannot invent arbitrary event names.

## `app_opened` v1 semantic definition

`app_opened` v1 means: **an authenticated LifeMate account successfully entered the authenticated product experience once in a new app process after account bootstrap completed**.

Important boundaries:

- v1 does **not** mean every foreground resume; lifecycle resume can become a separate versioned event later if a real measurement need appears;
- retries of account bootstrap in the same process/account do not create repeated `app_opened` events;
- signing into another account in the same process permits one event for the new account;
- the canonical analytics clock is the server `received_at_utc`, not an untrusted client clock;
- company-level active-user metrics deduplicate by canonical account, while product-scoped metrics may filter by `product`;
- no historical activity is backfilled from `last_active_at_utc` or another current-state snapshot.

## Allowed dimensions

A product event contains only:

- `kind=product`;
- a random event UUID used for idempotency;
- `application`: `wellmate` or `caremate`;
- bounded release version (`unknown` is valid when the caller does not yet have a reliable build version);
- coarse platform;
- one approved event name;
- `localeFamily`: `fa`, `en` or `other`;
- `connectivity`: `online`, `offline`, `recovering` or `unknown`;
- `outcome`: `success`, `failure`, `cancelled`, `queued`, `replayed` or `not_applicable`.

There is deliberately no arbitrary metadata object, free-form label, URL, route, user property or custom string dimension.

## Prohibited data

Product telemetry must never include or derive event dimensions from:

- auth subject, Account, AppUser, Person, relationship, invitation or request identifiers in the **client envelope**;
- email, phone, address, contact hash or raw invitation token;
- medication/treatment names, dose values/status detail, health observations or care-event content;
- cycle dates, symptoms, pregnancy/women-health details or user notes;
- caregiver/patient display names;
- raw API routes/URLs/query strings;
- exception messages, request/response bodies or raw stack traces;
- access tokens, authorization headers or provider credentials;
- any arbitrary metadata/free-text field.

The persisted table necessarily stores the canonical account foreign key so distinct-account business metrics and account deletion can be implemented correctly. That identifier is resolved by the server from the verified authenticated subject; it is never accepted from the client, returned to analytics dashboards, logged by telemetry, or combined with health payloads.

If a proposed metric requires other sensitive/raw fields, it is not eligible for this telemetry channel. It requires a separate privacy/security review and a different data contract.

## Server behavior

`lifemate-telemetry` authenticates the request and rate-limits by subject in memory. Product events are validated against the fixed schema, normalized to the canonical taxonomy, then persisted through the narrow authenticated `record_product_activity_event` RPC. The RPC resolves the canonical account from the authenticated subject and deduplicates by `event_id`.

The append-oriented `analytics.product_activity_events` table stores only the fixed dimensions above plus canonical account, definition version and server receive time. Direct `anon`/`authenticated` table access is revoked and RLS is enabled. Unknown fields, unknown event names and malformed dimensions fail closed. Database/provider error bodies are never forwarded to the client.

A duplicate `event_id` is an idempotent success/no-op. A persistence failure returns a bounded 503 from telemetry so the event is **not** falsely acknowledged as stored. Product analytics remains non-critical: the consumer reporter swallows delivery failures and never blocks an app journey.

## Client behavior

`LifeMateProductAnalytics` exposes enums for every allowed event and dimension. Callers cannot attach arbitrary metadata. The reporter sends only while the app is configured and an authenticated access token is available; failures are swallowed without printing sensitive context.

`LifeMateExperienceGate` emits one authenticated `app_opened` event after a successful account bootstrap in a process/account and deliberately does not emit another merely because the app resumes from background.

## Retention and deletion

Canonical product activity rows use `account_id ... on delete cascade`, so account deletion removes the account-linked analytics facts rather than retaining a shadow identity history. Any future longer-lived anonymized aggregate/rollup policy must be reviewed separately and must not make a deleted account re-identifiable.

No fabricated pre-instrumentation backfill is permitted. Dashboards must label earlier or partially covered periods as not instrumented/partial instead of zero-filling them.

## Reporting rule

Dashboards consume bounded aggregate/read-model contracts, not raw activity rows. They may aggregate counts/rates by the approved low-cardinality dimensions and release where reliable. They must not expose per-account timelines or attempt to reconstruct health/user behavior beyond the approved business-event definitions.

Active-user semantics are account-scoped. Company-level metrics deduplicate the same account across products; product filters are explicit. Definition version, source, freshness, scope and known limitations must accompany important metrics, with simple Persian operator copy in Command Center and technical details on demand.
