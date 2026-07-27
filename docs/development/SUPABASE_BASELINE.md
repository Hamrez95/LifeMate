# Supabase baseline

Project: `lifemate`
Region: `eu-west-1`
Project reference: `bwdvmniywyyijjauipnh`

## Current observed state
- Project restored and healthy.
- Supabase Auth is the configured mobile identity provider.
- EF migrations through `20260726222000_AddDoseAdherence` are deployed.
- A legacy/demo table exists at `public.health_status` and must not become the production source of truth.

## Deployment policy
- EF Core migrations in `backend-dotnet` are the source of truth for application schema.
- Apply migrations only after the corresponding pull request is green.
- Flutter clients do not directly mutate healthcare tables.
- Production secrets belong in environment/secret stores, never Git.
- Do not use a service-role key for end-user authentication.

## Immediate next steps
1. Deploy `LifeMate.Api` to an HTTPS container host.
2. Validate JWT issuer/audience/JWKS with controlled beta accounts.
3. Run patient/caregiver cross-user isolation smoke tests against production.
4. Complete defense-in-depth RLS hardening without granting Flutter direct
   healthcare-table access.
5. Retire `public.health_status` only after the Flutter demo path is migrated
   and rollback is no longer needed.
