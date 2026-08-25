# LifeMate Command Center architecture

## Status

This document describes the administrative control-plane foundation introduced for the LifeMate Command Center. The foundation is deliberately separate from the mobile healthcare runtime and is not a license to expose health tables to internal users.

The production business-schema migration owner remains `supabase/migrations`.

## Trust boundaries

```text
lifemate-admin (browser)
        |
        | Supabase Auth session
        | MFA / AAL2 required by Admin API
        v
supabase/functions/lifemate-admin-api
        |
        | server-side admin membership + capability RBAC
        | validation / correlation ID / audit / idempotency
        v
lifemate_admin_runtime
        |
        | explicit least-privilege PostgreSQL grants
        v
PostgreSQL
  admin / identity / core / ecosystem / network / security /
  consent / commerce / analytics

  lifemate health schema  ---> DENIED to ordinary admin runtime
  care health read models ---> DENIED to ordinary admin runtime
```

The browser may use Supabase's publishable credential for authentication. It must never receive a service-role credential, PostgreSQL password, privileged database URL, AI provider secret, payment secret or social publishing token.

## Separate authorization systems

LifeMate intentionally has multiple authorization concepts. They must not be collapsed into a single `role` flag.

### Healthcare authorization

`security.access_grants`, scopes, consent and relationship context govern whether one LifeMate account may access another person's data. This is the patient/caregiver boundary.

### Commercial entitlement

`commerce.entitlements` answers whether an account/person has a paid/free product capability. An entitlement never grants health-data access.

### Administrative authorization

The Command Center uses the separate `admin` trust domain:

- `admin.members`
- `admin.roles`
- `admin.permissions`
- `admin.member_roles`
- `admin.role_permissions`

Administrative permissions are capability based. Navigation visibility in `lifemate-admin` is only UX; the Admin API must enforce the permission on every restricted operation.

## Canonical Admin data-source map

The Command Center must have one explicit server-side source contract per surface. A schema migration may not silently switch a page to an empty replacement table, and the browser must never compensate with direct database access or a legacy fallback.

| Surface | Canonical server-side source | Migration/empty-state rule |
| --- | --- | --- |
| Users / User 360 identity | `admin.user_directory_v2` plus purpose-specific user-detail contracts | Missing read model is an unavailable/deployment condition, never a browser fallback to `lifemate.user_profiles` or `lifemate.app_users`. |
| Relationships | natural relations from `network.person_relationships`; care compatibility from `admin.care_relationship_directory_v1`; consent from `consent.consent_records`; technical access from `security.access_grants` | Natural relationship, Care relationship, Consent and Access Grant remain distinct. Existing care rows must not disappear during migration. |
| Support | privacy-minimized `admin.support_ticket_queue_v1` and purpose-specific support detail/audit contracts | No direct `lifemate.*` queue fallback. |
| Analytics | canonical identity/ecosystem analytics inputs and versioned analytics contracts | Legacy user-table fallback is forbidden; unavailable instrumentation stays explicit. |
| Commerce | `commerce.products`, `commerce.plans`, `commerce.subscriptions`, `commerce.entitlements`, `commerce.features`, pricing/promotion/trial contracts | Zero subscriptions/promotions can be a truthful business state; it must not be treated as migration loss without parity evidence. |
| Marketing | bounded `admin.marketing_campaigns_v1`, channel/content-calendar models and audited Admin mutation functions | Attribution/performance remains unavailable until a canonical analytics contract exists; no inferred ROAS/CAC. |
| Finance | `finance.actual_ledger_entries` and purpose-specific budget/read contracts | Actual, Budget and Forecast remain separate. Missing forecast/scenario sources are explicit unavailable, not inferred from actuals. |
| Security / Staff | `admin.members`, `admin.staff_profiles`, `admin.roles`, `admin.permissions`, `admin.member_roles`, `admin.role_permissions`, `admin.audit_events` | Workforce identity is separate from consumer identity; ordinary admin roles never inherit health access. |
| Operations | no canonical operational snapshot is currently defined | The Operations page must stay explicit `Unavailable` until the dedicated operational read model exists; direct browser health probing is forbidden. |

`supabase/functions/lifemate-admin-api/admin_data_model_parity_test.ts` is the source-level regression gate for these boundaries. Production schema deployment parity is separate evidence: a green source test does not prove that the corresponding migration/view is already present in the live Supabase project.

## Sensitive health information

Ordinary Admin API database credentials have no access to the compatibility health schema or care health read models.

Two elevated capabilities exist as policy identifiers:

- `health.read.elevated`
- `women_health.read.elevated`

Both are `role_assignable=false`. Founder, Super Admin and Security cannot obtain them from normal role membership.

Future sensitive User 360 endpoints must require all of the following:

1. authenticated AAL2 admin session;
2. active admin membership;
3. permission to request/use the workflow;
4. a subject-specific elevated-access request;
5. a meaningful reason;
6. approval according to the configured policy;
7. a non-expired limited time window;
8. an append-audited read event;
9. a response mapper that returns only the permitted category.

Private women-health notes remain stricter than general health information. A generic health elevation must not imply access to women-health private content.

## Audit

`admin.audit_events` is a dedicated administrative audit stream. The `lifemate_admin_runtime` role receives `SELECT` and `INSERT` but no `UPDATE`, `DELETE` or `TRUNCATE` privilege.

Audit events should contain identifiers, action, result, reason, correlation/request IDs and elevated-access state. Raw health payloads, auth tokens, secrets and private notes must not be copied into audit metadata.

## Database runtime identity

`lifemate_admin_runtime` is a dedicated login with:

- no superuser;
- no database/role creation;
- no RLS bypass;
- no inheritance;
- a bounded connection limit;
- an independent password stored in Supabase Vault on Supabase deployments.

The Admin API may use the platform bootstrap database connection only to retrieve the dedicated runtime password during startup. It refuses to fall back to the privileged bootstrap connection for application queries.

## Authentication

The Admin API validates the presented bearer session with Supabase Auth and then requires `aal2` for authenticated Command Center routes.

A configured one-time Founder bootstrap is tied to an exact Supabase Auth subject and is closed after initial administrative membership exists. Production bootstrap configuration is operational secret/configuration, not source code.

## Environments

At minimum the Command Center must keep Local, Preview/Staging and Production distinct.

- Local: no production credentials or production health records.
- Preview/Staging: synthetic or explicitly approved non-production data by default.
- Production: real admin membership, AAL2, production Admin API and production audit.

Preview deployments must not casually point at unrestricted production database credentials.

## Evolution rules

- Keep healthcare business logic in the existing healthcare API/runtime unless a separately reviewed cutover is performed.
- Do not add a generic SQL endpoint, arbitrary query tool or unrestricted AI database tool to the Admin API.
- Prefer purpose-specific read models for analytics and operational dashboards.
- Add mutations as vertical slices with capability checks, validation, idempotency, audit and denial tests.
- Do not grant the ordinary admin database role access to health tables merely to simplify a UI implementation.
