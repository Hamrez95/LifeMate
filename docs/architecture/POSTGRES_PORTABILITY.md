# LifeMate PostgreSQL portability contract

Parent: Foundation #261 / #170.

## Decision

The canonical LifeMate database is **LifeMate-owned PostgreSQL**, not a Supabase-specific schema contract. Supabase is the current managed PostgreSQL/Auth/Edge/Storage provider. A future database-host migration must not require redesigning Account/AppUser/Person, healthcare, consent/access, outbox, admin/support or recovery data models.

The repository directory remains named `supabase/` because it also contains current provider deployment packaging. Directory naming does not authorize provider-owned database dependencies inside canonical LifeMate migrations.

## Portable database boundary

The following are part of the portable PostgreSQL contract:

- `supabase/bootstrap/legacy_lifemate_baseline.sql`;
- ordered SQL in `supabase/migrations/`;
- LifeMate-owned schemas including `lifemate`, `identity`, `core`, `network`, `security`, `consent`, `ecosystem`, `integration`, `care`, `commerce`, `analytics`, `admin` and `support`;
- PostgreSQL roles/grants/RLS used by `lifemate_edge_runtime`, `lifemate_worker_runtime`, `lifemate_admin_runtime` and backup/recovery identities;
- standard PostgreSQL extensions explicitly provisioned by migrations, currently including `pgcrypto`;
- standard PostgreSQL connection strings consumed by the server runtime;
- provider-independent logical backup/restore using `pg_dump` / `pg_restore` and external workstation connection configuration.

A provider move may require creating equivalent PostgreSQL LOGIN/NOLOGIN roles, installing supported standard extensions and adjusting host/port/database/TLS/pooling configuration. Those are provisioning differences, not domain-schema rewrites.

### Backup-reader security exception

The application runtime roles (`lifemate_edge_runtime`, `lifemate_worker_runtime`, `lifemate_admin_runtime`) remain `NOBYPASSRLS` and non-elevated. The workstation logical-backup extraction role is intentionally different: PostgreSQL `pg_dump` of complete protected tables must bypass row-level security, so `lifemate_backup_reader` is a narrowly reviewed `NOLOGIN`, read-only, `BYPASSRLS` role. It must remain `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, `NOREPLICATION` and must not receive schema/table mutation privileges.

A separately provisioned workstation LOGIN may receive membership in `lifemate_backup_reader`; the operational `pg_dump` uses `--role=lifemate_backup_reader`. That LOGIN credential stays outside Git/CI and is not an application runtime credential. The deliberate `BYPASSRLS` extraction capability must never be generalized to Edge, worker or admin application runtimes.

## Forbidden canonical migration dependencies

Canonical LifeMate migrations must not query, join, constrain against or call provider-owned database surfaces such as:

- `auth.users`, `auth.uid()` or other provider Auth database helpers;
- `storage.objects` or provider Storage database internals;
- `realtime.*` provider internals;
- provider dashboard/project-ref APIs or provider CLI-generated dump formats.

Provider names may exist as **opaque data values** describing an external identity/provider type, for example `supabase_auth`. That is application metadata and is not a PostgreSQL dependency.

Authentication subjects are presented to the application adapter and mapped through LifeMate-owned identity tables/tokenization. Healthcare authorization must never require a query to a provider-owned Auth schema.

## Provider-specific components that are intentionally outside this guarantee

The following are still provider-specific today and must not be mislabeled as portable merely because the database is portable:

- Supabase Auth account/session/recovery/provider settings;
- Supabase Edge Functions deployment/runtime packaging and provider secret distribution;
- current profile/object storage provider operations;
- Supavisor production pooling configuration;
- hosted WAF/DNS/Redis/provider infrastructure controls.

Replacing those services may require adapter/deployment work. The portability guarantee in this document is narrower: **the canonical LifeMate PostgreSQL domain and recovery format remain reusable on another compatible PostgreSQL host**.

## Continuous proof

`postgres-portability` CI uses an unmodified `postgres:17.6-alpine` service container, applies the canonical baseline and every ordered migration, and verifies the expected LifeMate-owned schemas, restricted application runtime roles, the deliberately narrow backup-reader exception and onboarding/recovery controls. A source policy scans canonical SQL and rejects direct references to provider-owned Auth/Storage/Realtime database schemas/helpers.

This dedicated proof complements other PostgreSQL integration/role-journey tests. A green run means the current canonical schema bootstraps on vanilla PostgreSQL; it does not prove that provider-specific Auth, Edge, Storage, Redis, WAF or DNS have already been abstracted.

## Migration rule

Before changing database providers:

1. run this portability workflow on the intended PostgreSQL major version;
2. provision equivalent restricted runtime/migration/backup identities, preserving the narrow `NOLOGIN` backup-reader `BYPASSRLS` exception only for complete logical extraction;
3. run the encrypted workstation backup/isolated restore contract;
4. run patient/caregiver/unrelated authorization and consent/revocation journeys;
5. update only connection/pooling/provider adapter configuration where possible;
6. treat any proposed domain-table rewrite as a separate reviewed migration, never as an implicit provider-move requirement.
