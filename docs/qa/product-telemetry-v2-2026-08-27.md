# Product telemetry v2 / update policy evidence — 2026-08-27

Issue: #498

## Source/data model

- Version presence is Account-scoped and limited to Product, Platform, App Version, Build Number, optional rollout cohort, first/last seen timestamps and count.
- The ingestion parser rejects every unknown field, so device identifiers/fingerprints and arbitrary health/PII metadata cannot be appended by clients.
- `analytics.account_product_version_v1` supplies current/last-seen User 360 context.
- `analytics.product_version_adoption_v1` supplies aggregate adoption with definition/source/freshness metadata.
- Historical presence is bounded to 400 days by the canonical ingestion function.

## Update policy

- `platform.product_update_policies` is server-managed, versioned and archived on change.
- Soft update is the default.
- A Force policy is structurally invalid unless its reason is Critical, Security or BreakingCompatibility.
- The authenticated user API evaluates current semantic version against minimum/recommended policy and returns `current`, `soft` or `force`.
- No feature flag/update policy grants backend permission or entitlement.

## APIs/read models

User API:
- `POST /api/v1/product/version-presence`
- `GET /api/v1/product/update-policy`

Admin API (permission `analytics.product_versions.read`):
- `GET /api/v1/analytics/product-version-adoption`
- `GET /api/v1/analytics/accounts/:accountId/product-versions`
- `GET /api/v1/platform/product-update-policies`

These read models are sufficient for User 360, aggregate adoption and targeting decisions by later Campaign/Push integration without embedding raw health data.

## Verification

- Core unit tests cover payload allow-listing, SemVer prerelease/build ordering and force/soft/current decisions.
- Admin tests cover filter/path validation and privacy-minimized read-model mapping.
- Full migration-chain CI exercises PostgreSQL DDL/RLS/grants when GitHub runners execute.
- `tools/operations/verify-product-telemetry-v2.mjs` verifies source-level privacy/update-policy invariants.

GitHub-hosted runner infrastructure has recently failed before executable steps (`runner_id=0`, empty steps). That condition is infrastructure evidence, not a product pass or product-test failure.
