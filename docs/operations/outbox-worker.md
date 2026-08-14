# LifeMate durable outbox worker runbook

This runbook covers the `integration.outbox_messages` queue consumed by `supabase/functions/lifemate-worker`.

The outbox is for non-request-path work. Authoritative healthcare writes remain transactional in their owning API/database transaction. Do not move medication intake, treatment-plan state, consent decisions, or other source-of-truth medical writes into asynchronous best-effort processing merely to reduce latency.

## Queue policy

Lower numeric priority is processed first.

| Event family | Priority | Attempts | Maximum age |
| --- | ---: | ---: | ---: |
| `identity.session_revoke_requested` | 5 | 12 | 24h |
| `identity.account_deletion_requested` | 10 | 12 | 7d |
| `notification.*` | 40 | 6 | 24h |
| `care.adherence_projection_refresh_requested` | 60 | 8 | 6h |
| other | 70 | 6 | 24h |
| `analytics.*` | 80 | 6 | 6h |
| `maintenance.*` | 90 | 6 | 24h |

Worker batch size is bounded to 1-50 messages (`20` by default). Per-message downstream/database work is bounded by `LIFEMATE_WORKER_MESSAGE_TIMEOUT_MS`, accepted only between 1s and 20s (`8s` by default).

Retries use exponential backoff with jitter. Permanent validation/unsupported-event failures go directly to `DeadLetter`. Attempt exhaustion or message-age expiry also produces `DeadLetter` rather than an infinite retry loop.

Adherence projection refresh messages are coalesced by person/date while pending. One follow-up may still be created while a previous message is already processing, which prevents a hot aggregate from growing the queue without losing a later refresh.

## Health signals

The worker response contains aggregate queue metadata only; payloads are never returned.

`integration.outbox_queue_metrics(...)` exposes:

- `ready_count`
- `processing_count`
- `dead_letter_count`
- `oldest_ready_age_seconds`
- `highest_attempt_count`

Operational lag thresholds used by the worker:

- `< 120s`: `ok`
- `120-899s`: `warn`
- `>= 900s`: `critical`

A single warning is not automatically an incident. Investigate sustained `warn`, any `critical`, steadily increasing ready count, or newly growing dead-letter count.

## First-response checklist

1. Confirm worker invocation is succeeding and authentication is not returning `401`/`503`.
2. Inspect aggregate queue metrics before inspecting individual rows.
3. Identify whether lag is isolated to one event type.
4. Check dependency health (Supabase Auth for identity events, database health for projection work).
5. Do not increase batch size above the enforced maximum and do not remove retry delays to "catch up"; that can transfer the outage to PostgreSQL or the downstream provider.
6. Do not log `payload_json` in application or incident channels. Outbox payloads may contain health/account identifiers.

Example operator query (metadata only):

```sql
select *
from integration.outbox_queue_metrics(null);
```

Event-scoped example:

```sql
select *
from integration.outbox_queue_metrics(
  array['identity.session_revoke_requested']::character varying[]
);
```

## Dead-letter recovery

A dead-letter row is evidence that automatic processing intentionally stopped. Before requeueing, determine whether the dependency/problem is fixed and whether replay is safe for that event.

Review metadata without copying sensitive payloads into tickets or chat:

```sql
select id, event_type, status, attempt_count, last_error_code,
       created_at_utc, last_attempt_at_utc, dead_lettered_at_utc
from integration.outbox_messages
where status = 'DeadLetter'
order by dead_lettered_at_utc desc
limit 100;
```

Requeue exactly one reviewed message with an operator-owned database identity. The worker runtime role is intentionally not granted this function:

```sql
select integration.requeue_dead_letter_outbox_message(
  '<message-uuid>'::uuid,
  'dependency_recovered'
);
```

Requeue resets attempts and age for the reviewed row. It does not bypass the normal worker claim/retry policy.

Never bulk-requeue an unknown dead-letter population. Sample first, group by `event_type` and `last_error_code`, fix the root cause, then requeue in small bounded batches while observing lag and database/downstream health.

## Stale worker locks

Claims older than 10 minutes are treated as abandoned. The next claim pass converts non-expired stale work back to retryable `Failed` state and can reclaim it. Expired stale work becomes `DeadLetter`.

Do not manually clear active locks merely because a worker invocation is slow. Confirm the lock age and dependency state first.

## Consumer replay safety

`integration.outbox_consumer_receipts` records completed consumer handling by `(message_id, consumer_name)`. The current supported handlers are designed to be replay-safe:

- adherence summary rebuild is a deterministic projection rebuild;
- Supabase session revocation is an idempotent account-state update;
- account deletion finalization now treats an already completed deletion request as success.

When adding a new event consumer, do not rely on receipts alone for an irreversible external side effect. The crash window between an external side effect and receipt persistence still exists. Use a provider idempotency key, deterministic external resource key, or another event-specific deduplication mechanism before enabling retries.

## Retention

Processed messages are pruned after 7 days and dead letters after 30 days, in bounded batches. Retention cleanup is intentionally incremental so housekeeping cannot monopolize the database.

Do not shorten dead-letter retention during an active incident; those rows are the operational evidence needed to understand and safely replay failures.
