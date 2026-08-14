# LifeMate offline mutation policy

## Closed-beta scope

LifeMate does **not** make every write offline-capable. The closed-beta durable allowlist contains only medication dose adherence reports:

`POST /api/v1/dose-occurrences/{occurrenceId}/report`

This route already has a server-side `clientRequestId`, idempotency protection and optimistic version checks. Profile edits, invitations, relationships, care-event creation, consent changes and other writes remain online-only until they have an explicit conflict/pending UX and a server contract that makes delayed replay safe.

## Persistence and privacy

Queued dose payloads are health data. They are stored with `flutter_secure_storage` and are isolated by authenticated Supabase account ID. Each action uses its own deterministic secure-storage key so foreground and Android home-widget isolates cannot overwrite one shared JSON list.

The queue never stores an access token, refresh token, password, email address, caregiver identity or API secret. Replay obtains the **current** session token. A queued URI must still match the current configured LifeMate API origin and the exact dose-report allowlist before a token can be attached.

## Delivery semantics

The client journals the exact request body and `clientRequestId` before the first transport attempt. If the response is lost, retrying the same request remains safe because the server idempotency contract owns the final result.

A queued mutation remains pending on transport timeout, `401`, `408`, `429` or `5xx`. A later authenticated resume/bootstrap/reconnect replays FIFO using the current token. An account switch stops replay immediately.

A definitive non-retryable `4xx` response removes the historical mutation because the server rejected that exact version/intent; the next normal read is authoritative. Client UI must never label a locally queued action as server-confirmed success: it is shown as `pending_sync` until replay succeeds.

## Bounded storage

- maximum queued actions: 100;
- retention window: 7 days;
- no oldest-item eviction when full: a new enqueue fails rather than silently deleting a previously acknowledged local action;
- malformed or expired entries are not replayed;
- queue loss caused by app uninstall/device secure-storage reset is outside the closed-beta offline guarantee.

The 7-day window is intentionally much longer than the expected "hours without connectivity" use case while preventing indefinite health-data retention on an offline/lost device.

## Verification required before stable beta

Automated tests cover deduplication, account isolation, separate queue instances, offline-to-reconnect replay, expired-token retention followed by fresh-token replay, account switching, API-origin pinning, non-allowlisted writes and pending-state projection.

Physical QA still must cover airplane mode, process kill/relaunch, background/foreground transitions and the Android medication widget. Automation does not mark those device checks passed.
