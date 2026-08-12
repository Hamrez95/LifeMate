# LifeMate

LifeMate is a multi-application digital-health and family ecosystem. A single login account can represent one person while also being granted explicit, revocable access to other people such as a parent, spouse or child. Future professional roles are contextual rather than fixed properties of a user.

## Current products

- **WellMate** — self/patient Flutter application for medication, treatment, appointments and health tracking.
- **CareMate** — caregiver/family Flutter application for consent-scoped monitoring and support.
- **Women Health pilot** — high-sensitivity tracking inside the current product surface with explicit companion-summary sharing.
- **LifeMate closed-beta API** — Supabase Edge runtime for authenticated healthcare workflows.
- **LifeMate Command Center foundation** — internal management UI in the separate `lifemate-admin` repository with a distinct `lifemate-admin-api` trust boundary in this repository; production rollout is gated separately.
- **ASP.NET Core reference backend** — domain/reference implementation and parity tests; it is not the current mobile healthcare runtime.

## Current healthcare runtime

```text
WellMate / CareMate
        |
        | Supabase Auth session + HTTPS
        v
Supabase Edge Function: lifemate-api
        |
        | bounded server DB connection
        v
PostgreSQL
  identity / core / ecosystem / security / consent / commerce / integration / analytics
  + lifemate compatibility health tables during migration
```

Mobile clients never directly read or mutate healthcare tables and never receive database/service-role credentials.

## Command Center boundary

```text
lifemate-admin
        |
        | Supabase Auth + MFA/AAL2
        v
Supabase Edge Function: lifemate-admin-api
        |
        | admin membership + capability RBAC
        v
lifemate_admin_runtime
        |
        v
approved management tables/read models

ordinary raw-health access: denied
```

The administrative trust domain is separate from caregiver access grants and commercial entitlement. Raw health access is not an ordinary Founder/Super Admin capability; future sensitive access uses a subject-specific, time-limited and audited elevation workflow.

## Data foundation

The ecosystem refactor separates:

- **Account** — stable LifeMate login principal with one or more external identities.
- **Person** — human/data subject; may exist without an account (child/dependent).
- **Relationship/engagement** — human or domain context.
- **Access grant + scope** — what an account may do with a person's data.
- **Consent** — versioned purpose/data-category decision and append-oriented history.
- **Entitlement** — commercial capability from free, subscription, trial, gift, family, organization or other sources.
- **Admin capability** — internal staff authorization inside the separate Command Center control plane.

Paid entitlement or administrative staff role never replaces health-data authorization or consent.

## Canonical schema ownership

`supabase/migrations/*.sql` is the single forward production business-schema migration chain and uses portable PostgreSQL. The existing four EF Core migrations under `backend-dotnet` are frozen historical bootstrap artifacts. Supabase-specific Auth/Storage operational SQL is isolated under `supabase/infrastructure/`.

`.github/workflows/schema.yml` proves the SQL chain on fresh PostgreSQL and verifies ecosystem/privacy/admin invariants. This removes the previous split where EF created the base and later SQL files evolved the live database.

## Repository map

```text
wellmate/                               Flutter self/patient application
caremate/                               Flutter caregiver/family application
packages/lifemate_client/               Shared authenticated mobile client
supabase/functions/lifemate-api/        Current healthcare API runtime
supabase/functions/lifemate-admin-api/  Internal Command Center API boundary
supabase/migrations/                    Canonical portable PostgreSQL migrations
supabase/infrastructure/                Supabase-specific operational configuration
backend-dotnet/                         ASP.NET Core domain/reference implementation and tests
backend/                                Legacy Dart/Shelf demo; not production
docs/architecture/                      Ecosystem/data/security/Admin architecture
docs/security/                          Threat models and data classification
docs/privacy/                           Consent/provenance/de-identification policy
docs/compliance/                        Google Play health/data-safety mapping
docs/migrations/                        Migration/rollback plans
```

## Verification

### Database

The authoritative migration workflow applies all canonical SQL in lexical order to fresh PostgreSQL 17, asserts Account/Person/access/consent/entitlement/outbox/Admin constraints and proves commercial export and ordinary Admin health access remain fail-closed.

### Healthcare Edge API

```bash
cd supabase/functions/lifemate-api
deno fmt --check
deno task check
deno task test
```

### Admin Edge API

```bash
cd supabase/functions/lifemate-admin-api
deno fmt --check
deno task check
deno task test
```

Integration/schema/restore CI uses the same canonical SQL migration chain.

### ASP.NET Core reference

```bash
dotnet restore backend-dotnet/LifeMate.sln
dotnet build backend-dotnet/LifeMate.sln --configuration Release --no-restore
dotnet test backend-dotnet/LifeMate.sln --configuration Release --no-build
```

### Flutter

Run dependency resolution, analysis and tests from each application directory. Exact SDK versions and commands live in `.github/workflows/flutter.yml`.

## Safety rules

- Never commit secrets, tokens, production connection strings, signing keystores, PII or health data.
- Keep authentication, ownership, consent, cross-person authorization, entitlement, admin capability checks, idempotency and revocation server-side.
- Women-health private notes are owner-only; a caregiver relationship or ordinary admin role is never sufficient to expose them.
- Commercial/pharma secondary use is disabled by default. Health Connect / Android health-permission data is not eligible for commercial export.
- No destructive reset is permitted on an environment unless every record is proven disposable.
- Apply live migrations only after review/CI and use forward corrective migrations rather than destructive down migrations for health data.

See [AGENTS.md](AGENTS.md), [ecosystem data model](docs/architecture/ecosystem-data-model.md), [Command Center architecture](docs/architecture/admin-command-center.md), [Admin threat model](docs/security/admin-threat-model.md), [migration plan](docs/migrations/ecosystem-refactor.md) and [Google Play health compliance map](docs/compliance/google-play-health.md).
