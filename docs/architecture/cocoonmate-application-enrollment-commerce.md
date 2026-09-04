# CocoonMate application, enrollment and Commerce boundary

Status: Phase 1 contract for issue #782.

## Independent state machines

Cocoon bootstrap must never collapse these into one boolean:

1. **Application availability** — canonical `ecosystem.applications(code='cocoonmate')` and its Active/Disabled state.
2. **Application enrollment** — `ecosystem.app_enrollments` for the authenticated Account. Enrollment records explicit Cocoon app use only.
3. **Experience eligibility** — authenticated Account has the canonical Self Person context required by Cocoon.
4. **Commerce eligibility** — existing `commerce` product/subscription/offer and Period→Cocoon conversion state.
5. **Pregnancy lifecycle** — canonical Person-owned `pregnancy.episodes` state.
6. **Health sharing authorization** — typed pregnancy scope + access grant + consent; relationship and Commerce never authorize PHI.

## Enrollment timing

Cocoon is **not** backfilled into every existing LifeMate account. The first authenticated request to the Cocoon API creates an `Active` Cocoon enrollment when the canonical application is Active and no enrollment exists. This is an idempotent `account_id + application_id` operation.

Existing `Suspended` or `Left` enrollment is not silently reactivated. Disabled/missing application state fails closed before a pregnancy route runs.

Enrollment creation/update writes only `ecosystem.app_enrollments`. It must not create or mutate:

- pregnancy episodes or dating;
- Commerce subscription/entitlement/payment rows;
- relationships or access grants;
- consent records.

Because Cocoon enrollment can imply use of a reproductive-health product, ordinary marketing analytics and general User 360 must not expose it as a raw segmentation attribute. Product-health reporting should use privacy-minimized aggregates.

## Bootstrap contract

The frozen v1 pregnancy bootstrap keeps its existing `enrollmentState` field for backward compatibility; that field is pregnancy lifecycle state. #782 adds independent additive fields:

- `applicationState.availability`: `available | unavailable`
- `applicationState.enrollmentState`: `active | suspended | left | not_enrolled`
- `experienceEligibility.state`: currently `eligible` after canonical Self Person resolution
- `commerceEligibility.state`: `entitled | conversion_eligible | offer_available | not_entitled | unavailable | error`
- `commerceEligibility.offerAvailable`
- `commerceEligibility.conversionEligible`

Old v1 clients ignore these additive fields. Updated `lifemate_client` parses missing fields as `unknown` so it remains compatible with older servers during rollout.

## Commerce source of truth

No Cocoon-specific billing tables are introduced.

- Product: existing `commerce.products(code='cocoonmate')`.
- Direct entitlement state: existing canonical Cocoon subscription records.
- Offers: existing `commerce.offers` and product lifecycle publication state.
- Period conversion: eligibility mirrors prerequisites of canonical `commerce.convert_period_to_cocoon(...)` — active paid Period subscription, payment provenance/effective collected value, remaining service period, no prior conversion and no already-active Cocoon subscription.

The existing conversion mutation remains the only write path. Bootstrap only reads eligibility and never performs a conversion or issues entitlement.

A Cocoon entitlement does not create a pregnancy episode. A pregnancy episode does not create a Cocoon entitlement. An unrelated product entitlement never satisfies the Cocoon product checks.

## Failure semantics

- missing/Disabled Cocoon application → `503 cocoon_application_unavailable`
- Suspended/Left enrollment → `403 cocoon_application_enrollment_inactive`
- Commerce read failure → `commerceEligibility.state=error`; health authorization is unaffected
- Commerce unavailable/hidden without an eligible paid Period conversion → no paid activation is inferred

Pregnancy authorization still executes inside the canonical pregnancy handler after the application boundary. No application or Commerce state can bypass `pregnancy.owner.manage` / `pregnancy.summary.read` enforcement.
