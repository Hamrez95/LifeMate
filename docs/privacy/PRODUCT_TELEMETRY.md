# Privacy-safe product telemetry

Parent: #263 / #53.

## Purpose

LifeMate product analytics measures coarse activation and reliability funnels without turning telemetry into a second copy of health or identity data. The telemetry endpoint is authenticated, but the authenticated subject is used only for admission/rate limiting and is never included in the logged event envelope.

Crash telemetry remains a separate backwards-compatible envelope. Product events are accepted only when `kind=product` and every field matches this document and the server parser.

## Approved product events

Only these fixed event names are permitted:

- `app_open`
- `auth_login_succeeded`
- `auth_session_restored`
- `onboarding_started`
- `onboarding_completed`
- `care_pairing_started`
- `care_pairing_completed`
- `care_access_revoked`
- `offline_queue_enqueued`
- `offline_queue_recovered`

Adding an event requires a reviewed source change to both the server allowlist and shared client enum. Runtime code cannot invent arbitrary event names.

## Allowed dimensions

A product event contains only:

- `kind=product`;
- a random event UUID;
- `application`: `wellmate` or `caremate`;
- bounded release version;
- coarse platform;
- one approved event name;
- `localeFamily`: `fa`, `en` or `other`;
- `connectivity`: `online`, `offline`, `recovering` or `unknown`;
- `outcome`: `success`, `failure`, `cancelled`, `queued`, `replayed` or `not_applicable`.

There is deliberately no arbitrary metadata object, free-form label, URL, route, user property or custom string dimension.

## Prohibited data

Product telemetry must never include or derive event dimensions from:

- Auth subject, Account, AppUser, Person, relationship, invitation or request identifiers;
- email, phone, address, contact hash or raw invitation token;
- medication/treatment names, dose values/status detail, health observations or care-event content;
- cycle dates, symptoms, pregnancy/women-health details or user notes;
- caregiver/patient display names;
- raw API routes/URLs/query strings;
- exception messages, request/response bodies or raw stack traces;
- access tokens, authorization headers or provider credentials;
- any arbitrary metadata/free-text field.

If a proposed metric requires one of these fields, it is not eligible for this telemetry channel. It requires a separate privacy/security review and a different data contract.

## Server behavior

`lifemate-telemetry` authenticates the request and rate-limits by subject in memory, but it logs only the validated event envelope. Unknown fields, unknown event names and malformed dimensions fail closed with a validation error. Product analytics is non-critical and must never block an app journey.

## Client behavior

`LifeMateProductAnalytics` exposes enums for every allowed event and dimension. Callers cannot attach arbitrary metadata. The reporter sends only while the app is configured and an authenticated access token is available; failures are swallowed without printing sensitive context.

## Reporting rule

Dashboards may aggregate counts/rates by the allow-listed dimensions and release. They must not attempt to reconstruct individual user timelines. Crash-free and activation metrics are operational/product aggregates, not patient records.
