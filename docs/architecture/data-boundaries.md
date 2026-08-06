# Data boundaries

Target PostgreSQL schema boundaries:

- `identity`: accounts, external identities, contact points, deletion requests.
- `core`: persons, profiles, account-person links.
- `ecosystem`: applications and enrollment.
- `network`: natural person relationships.
- `security`: access scopes/grants, classification/retention policy metadata.
- `consent`: documents, records, immutable consent events and secondary-use consent.
- `commerce`: product/plan/feature/price/subscription/entitlement foundation.
- existing `lifemate`: compatibility treatment/care/women-health transactional tables during phased migration.
- `integration`: transactional outbox.
- `analytics`: policy boundary and export audit; no external raw OLTP access.

Future `pregnancy`, `baby`, `fitness` and `clinical` schemas are created only when real features require them.

## PII versus health data

Health tables reference `person_id`; they do not depend on email, phone, Google subject, device ID or payment identifiers. Presentation profile data lives in `core.person_profiles`; contact identity lives in `identity.contact_points`; billing lives in `commerce`.

## Portability

Core schemas use standard PostgreSQL types, constraints and transactions. Supabase Auth, Storage and Edge are infrastructure adapters. The healthcare domain never receives a Supabase service-role credential in a client. This keeps migration to managed/self-hosted PostgreSQL feasible.

## Residency

Accounts/persons may carry an optional home/data-region code (`IR`, `EU`, future regions). It is metadata for future routing/policy, not an attempt to build a premature multi-region database. IDs remain globally unique and future domain extraction must not introduce unavoidable cross-region synchronous joins.
