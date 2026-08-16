# LifeMate Command Center read-only advisor

`ADM-AI-001` introduces a bounded internal advisor for operational/product insight. Phase 1 deliberately does **not** connect an external LLM. The endpoint always returns a deterministic, evidence-backed result so model availability cannot remove source/freshness evidence or widen the data boundary.

## Endpoint

`POST /api/v1/ai/advisor/insights`

The request accepts only:

- an allowlisted `topic`: `product_overview`, `acquisition`, or `activity`;
- an optional human question of 2–500 characters.

The question is treated as untrusted data. It is not interpolated into SQL, prompts, URLs, connector calls, file paths, or provider requests. Topic selection alone determines the fixed source allowlist.

## Authorization

The caller must have:

1. `ai.advisor.read`; and
2. every underlying source permission for the selected topic.

Phase 1 topics use approved analytics read models and therefore also require `analytics.read`. The new advisor permission is granted automatically only to `founder` and `super_admin`; later role changes belong in the security/admin-membership workflow.

## Approved sources

Phase 1 is intentionally small:

| Topic | KPI allowlist | Source permission |
| --- | --- | --- |
| `product_overview` | `accounts_created`, `monthly_active_accounts` | `analytics.read` |
| `acquisition` | `accounts_created` | `analytics.read` |
| `activity` | `monthly_active_accounts` | `analytics.read` |

The implementation reuses the canonical analytics KPI store and its existing privacy-minimized contracts. It does not query raw health data, Women Health data, contacts, provider credentials, Vault, free-form SQL, or arbitrary schemas.

## Output contract

Every response contains:

- `mode: deterministic`;
- a short grounded summary;
- findings with `info` or `attention` severity;
- evidence objects with stable source identifiers, source text, value state, exact freshness and caveat;
- explicit caveats;
- a generated timestamp;
- model status showing the deterministic fallback is in use.

Missing or uninstrumented evidence remains `unavailable`. The advisor must never turn missing data into zero and must never invent metrics.

## Side-effect boundary

The endpoint is read-only. It has no idempotency/mutation workflow because it does not change state. It cannot:

- write database rows;
- enqueue outbox work;
- publish to providers;
- invoke arbitrary web/connectors;
- return provider secrets or model keys;
- bypass the source permission intersection.

Operational logging records only correlation id, allowlisted topic, whether a question was supplied, question length, evidence count and advisor mode. Raw question text is not logged.

## Future model gateway

A future PR may add a server-side model adapter behind this same contract. Before enabling one, it must preserve the deterministic context assembler, source allowlist, permission intersection, privacy minimization, strict structured output validation, bounded timeout/cost policy, and deterministic fallback. Browser code must never receive a model/provider secret.
