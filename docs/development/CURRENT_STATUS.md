# Current development status

Last updated: 2026-07-27

## Completed
- Backend foundation and green CI gate
- Supabase project restored and healthy
- Product beta scope and version plan documented
- Cross-functional critic gates documented
- v0.2 care relationships merged
- v0.3 treatment management merged
- v0.4 adherence engine merged and deployed to Supabase
- v0.5 production Flutter integration in active draft

## Supabase observation
- Project: `lifemate` (`bwdvmniywyyijjauipnh`)
- Region: `eu-west-1`
- Status at audit: healthy
- Production schema migrations through `add_dose_adherence`: deployed
- Legacy/demo table: `public.health_status`

## Active milestone
v0.5–v0.7 — complete the real patient/caregiver loop, reminders, API hosting,
Android release gates, and beta APKs.

## Founder action currently required
Resolve GitHub Actions billing/spending limits. Before usable APKs can be built,
select an HTTPS container host for `LifeMate.Api` and configure the three public
mobile build variables. Do not expose secrets or configure paid SMS.
