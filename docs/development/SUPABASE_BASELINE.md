# Supabase baseline

Project: `lifemate`
Region: `eu-west-1`
Project reference: `bwdvmniywyyijjauipnh`

## Current observed state
- Project restored and healthy.
- Supabase Auth is initialized with no application users yet.
- The production `lifemate` schema has not yet been deployed.
- A legacy/demo table exists at `public.health_status` and must not become the production source of truth.

## Deployment policy
- EF Core migrations in `backend-dotnet` are the source of truth for application schema.
- Apply migrations only after the corresponding pull request is green.
- Flutter clients do not directly mutate healthcare tables.
- Production secrets belong in environment/secret stores, never Git.
- Do not use a service-role key for end-user authentication.

## Immediate next steps
1. Implement v0.2 care invitations and relationships locally with PostgreSQL integration tests.
2. Merge only with green CI.
3. Apply the verified EF migration to this Supabase project.
4. Validate JWT issuer/audience/JWKS against Supabase Auth.
5. Create controlled test accounts and prove cross-user isolation.
6. Retire `public.health_status` only after the Flutter demo path is migrated and rollback is no longer needed.
