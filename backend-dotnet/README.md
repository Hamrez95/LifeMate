# LifeMate production backend foundation

`backend-dotnet` is the production backend foundation for LifeMate. It is an ASP.NET Core modular monolith targeting .NET 10 with EF Core and PostgreSQL. The existing Dart/Shelf backend remains untouched as a temporary demo backend.

## Architecture

Dependency direction:

- `LifeMate.Domain`: domain models and domain exceptions only.
- `LifeMate.Application`: use cases and interfaces; references Domain.
- `LifeMate.Infrastructure`: EF Core, PostgreSQL, persistence, migrations, and adapters; references Application and Domain.
- `LifeMate.Api`: HTTP endpoints, authentication, middleware, health checks, OpenAPI, and dependency registration; references Application and Infrastructure.

No ASP.NET Identity, MediatR, AutoMapper, queues, Redis, brokers, or Supabase client libraries are used in this PR.

## Zero-Cost Development Setup

1. Install free local tools: Docker Desktop or Docker Engine, and the .NET 10 SDK.
2. Start PostgreSQL locally. The Compose file binds PostgreSQL to `127.0.0.1:54329` only, uses development-only placeholder credentials, and stores data in the named Docker volume `lifemate-postgres-data`:

   ```bash
   docker compose -f backend-dotnet/docker-compose.yml up -d postgres
   ```

3. Restore packages:

   ```bash
   dotnet restore backend-dotnet/LifeMate.sln
   ```

4. Restore repository-local tools and apply migrations to the local database:

   ```bash
   dotnet tool restore
   dotnet ef database update --project backend-dotnet/src/LifeMate.Infrastructure --startup-project backend-dotnet/src/LifeMate.Api
   ```

5. Run the API:

   ```bash
   dotnet run --project backend-dotnet/src/LifeMate.Api
   ```

6. Run tests:

   ```bash
   dotnet test backend-dotnet/LifeMate.sln
   ```

This setup requires no paid cloud subscription, no SMS, no email delivery, no paid Supabase plan, and no production secrets.

## Configuration

Use environment variables or standard ASP.NET Core configuration. `.env.example` contains placeholders only.

Expected variables:

- `ConnectionStrings__LifeMateDb`: PostgreSQL connection string. Use local Docker for development and Supabase PostgreSQL in shared hosted environments.
- `Authentication__Supabase__Issuer`: Supabase Auth issuer, normally `https://PROJECT_REF.supabase.co/auth/v1`.
- `Authentication__Supabase__Audience`: expected JWT audience, commonly `authenticated` for Supabase user access tokens.
- `Authentication__Supabase__JwksUri`: Supabase JWKS endpoint, `https://PROJECT_REF.supabase.co/auth/v1/.well-known/jwks.json`.
- `Authentication__Supabase__MetadataAddress`: optional OIDC metadata endpoint if used instead of direct JWKS configuration.
- `Authentication__Supabase__RequireHttpsMetadata`: `true` outside local development.
- `Cors__AllowedOrigins__0`: allowed Flutter/web development origin.
- `OpenApi__Enabled`: set to `true` only when OpenAPI must be exposed outside Development.

## Test authentication versus Supabase authentication

Integration tests replace JWT bearer authentication with an in-test authentication handler that accepts `Authorization: Test <subject>` and creates only `sub`/name-identifier claims. That handler is registered from the test project only through `WebApplicationFactory` and is not part of production API startup. Local zero-cost development can run health checks and OpenAPI without a Supabase account, but authenticated manual API calls require either test-hosted integration tests or a real Supabase Free project access token.

## Supabase Auth JWT validation

Supabase Auth issues user access tokens as JWTs. Official Supabase JWT documentation says projects expose a JWKS endpoint at `https://project-id.supabase.co/auth/v1/.well-known/jwks.json` and recommends using high-quality JWT verification libraries rather than implementing JWT cryptography manually. LifeMate.Api uses ASP.NET Core JWT bearer authentication and Microsoft token validation libraries.

Do not use Supabase service-role keys for user authentication. Do not store JWTs, refresh tokens, OTPs, passwords, or Supabase keys in the application database.

## Initial beta authentication

For the initial beta, use Supabase email-based authentication in the Flutter apps to obtain a user access token. The apps then call LifeMate.Api with `Authorization: Bearer <access-token>`. Flutter clients must not directly read or mutate core healthcare tables.

## Endpoints

- `GET /health/live`: anonymous liveness check.
- `GET /health/ready`: anonymous readiness check that verifies database connectivity.
- `POST /api/v1/users/bootstrap`: authenticated, idempotently provisions the current JWT subject.
- `GET /api/v1/me`: authenticated current-user lookup.
- `PUT /api/v1/me/profile`: authenticated current-user profile update.

## EF Core migrations

Create a migration:

```bash
dotnet ef migrations add MigrationName --project backend-dotnet/src/LifeMate.Infrastructure --startup-project backend-dotnet/src/LifeMate.Api --output-dir Persistence/Migrations
```

Apply migrations:

```bash
dotnet ef database update --project backend-dotnet/src/LifeMate.Infrastructure --startup-project backend-dotnet/src/LifeMate.Api
```

Do not manually edit generated migrations after review. Create a follow-up migration instead.

## Cost notes

PR-01 introduces no recurring paid service. PostgreSQL runs locally through Docker. Supabase Free Plan can be used later for shared development PostgreSQL/Auth, but this PR does not require Supabase Pro-only features, paid backups, paid hosting, Redis, brokers, Firebase, SMS, or paid observability tools.
