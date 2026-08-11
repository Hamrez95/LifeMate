# LifeMate offline mutation policy

For the closed beta, offline replay is intentionally narrow.

## Queued now

- WellMate medication adherence: `POST /api/v1/dose-occurrences/{id}/report`
- Requires an existing `clientRequestId`; the server already enforces idempotency/version checks.

## Not queued automatically

Profile edits, invitations, relationship/consent changes, caregiver writes, treatment/event creation, account deletion, and other health-record writes stay online-only. Replaying these after a long disconnect could violate a newer permission, version, or user intent unless their UI explicitly models a pending state.

## Storage and replay rules

- Payloads are persisted only in platform encrypted secure storage (`flutter_secure_storage`), never SharedPreferences/plain JSON files.
- Access/JWT tokens are never persisted with a queued mutation.
- Queue rows are isolated by authenticated account ID.
- Queue is capped at 100 items and expires items after 7 days.
- Reconnect replay obtains the current access token.
- 2xx removes a pending mutation.
- Terminal 4xx removes it because the server has rejected the stale/revoked action.
- 401, 408, 429, network and 5xx retain it for a later authenticated retry.
- Replay is FIFO and stops at the first transient/auth failure.

This policy is deliberately fail-closed: adding another endpoint requires both server idempotency and a UI that can truthfully show its pending/synced state.
