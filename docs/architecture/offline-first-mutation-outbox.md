# LifeMate offline-first durable mutation outbox

Issue: #831 (`OFFLINE-03`)

## Canonical boundary

- Server remains canonical shared truth.
- The device outbox is a durable execution journal for user actions that were accepted locally but are not yet server-confirmed.
- The outbox reuses `LifeMateLocalHealthStore` from #829. Products must not create a parallel SQLite database, secure-storage JSON queue, or per-product outbox.
- Authentication tokens are never persisted in the outbox. Replay obtains a fresh token at execution time.
- Persist only API-relative endpoint paths. Never persist an old deployment origin and replay it after an environment/configuration change.

## Namespace and envelope

Every mutation is scoped by the #829 namespace:

`environment -> account -> person`

Every encrypted mutation envelope contains:

- stable `mutationId` / idempotency identifier;
- explicit health `domain`;
- stable logical `sourceKey`;
- HTTP method and API-relative endpoint path;
- protected request payload;
- local UTC creation time and IANA timezone;
- expected source/server revision when required;
- durable sync state, retry attempt count, retry eligibility time and low-cardinality error class.

The UI must distinguish locally accepted/pending, retry scheduled, conflict/rejected, and a transient server-confirmed acknowledgement. A queued action must never be rendered as server-confirmed before acknowledgement.

## Conflict policy is domain-specific

There is deliberately no global last-write-wins mode.

| Domain | Policy |
| --- | --- |
| adherence | idempotent logical event |
| treatment | explicit version resolution |
| care event / appointment | explicit version resolution |
| Women Health | deduplicate + merge |
| pregnancy dating | never silent last-write-wins |
| observation/check-in/symptom | duplicate prevention / merge |
| shared authorization | fail closed after authoritative revocation |

A `409` is not acknowledgement. Conflicting mutations remain durable until the domain resolver or user flow resolves them.

## Retry safety

- Transport, authentication, throttling and 5xx failures retain the mutation.
- Retry uses bounded exponential backoff; no tight foreground/background loop.
- Terminal client rejection remains visible as rejected rather than being silently deleted.
- Outbox capacity fails before accepting another action; accepted actions are not TTL-evicted.
- Telemetry may report counts/error classes only. It must not emit mutation IDs, source keys, endpoint parameters, request bodies, account/person IDs, health values, or server error messages.

## Reconnect and projections

A reconnect worker should:

1. refresh authorization and runtime configuration;
2. replay only eligible mutations in the active environment/account/person namespace;
3. acknowledge exactly one mutation for one successful idempotency ID;
4. retain/reclassify conflicts and retryable failures;
5. pull canonical changes incrementally using per-domain cursor/version contracts;
6. merge canonical records transactionally into the #829 local projection;
7. preserve unacknowledged local mutations during merge;
8. regenerate only affected future reminder projections through the shared #830 scheduler.

Remote/shared authorization is authoritative: revoked access must fail closed on refresh, while an owner mutation that merely cannot sync because auth is temporarily expired remains locally durable.

## Migration from the legacy queue

`lifemate_client` currently has a small `flutter_secure_storage` queue for idempotent dose reports. #831 migration must preserve existing accepted legacy items while moving new writes to this structured outbox. The compatibility layer must not erase the old queue until each legacy mutation is safely imported or acknowledged.

## Verification

Automated coverage must include:

- restart persistence and namespace isolation;
- stable-ID deduplication and ID-reuse rejection;
- bounded retry/backoff and expired-auth retention;
- exactly-one acknowledgement;
- durable `409` conflicts with explicit pregnancy-dating no-LWW policy;
- unsafe/old-origin rejection;
- multi-device/domain-policy tests at the client/API boundary;
- privacy contract: no PHI in retry telemetry/logs.

Physical network-kill/restart/reconnect behavior remains a device evidence gate where applicable and must not be marked complete solely from unit tests.
