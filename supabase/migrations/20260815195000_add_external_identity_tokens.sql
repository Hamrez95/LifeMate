-- Foundation #217 phase 1: create an additive storage boundary for keyed,
-- opaque external-identity lookup tokens. This table intentionally cannot store
-- a raw auth/provider subject. The HMAC key is supplied by the application from
-- provider/runtime secret management and must never live in PostgreSQL/Vault.
--
-- This migration does NOT claim database-breach unlinkability yet: legacy
-- `lifemate.app_users.auth_subject`, `identity.external_identities.provider_subject`,
-- profile PII and healthcare `*_user_id` compatibility columns still exist and
-- must be retired by later reviewed phases before #217 can close.

create table if not exists identity.external_identity_tokens (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references identity.accounts(id) on delete cascade,
    provider character varying(80) not null,
    issuer character varying(255) not null,
    subject_token character(64) not null,
    key_version integer not null check (key_version between 1 and 65535),
    status character varying(24) not null default 'Active'
        check (status in ('Active','Unlinked','Disabled')),
    created_at_utc timestamp with time zone not null default now(),
    last_authenticated_at_utc timestamp with time zone,
    constraint ck_external_identity_tokens_subject_token_hex
      check (subject_token ~ '^[0-9a-f]{64}$'),
    unique(provider, issuer, key_version, subject_token)
);

create index if not exists ix_external_identity_tokens_account_status
    on identity.external_identity_tokens(account_id, status);

comment on table identity.external_identity_tokens is
  'Opaque HMAC identity lookup tokens only; raw auth/provider subjects are forbidden.';
comment on column identity.external_identity_tokens.subject_token is
  'HMAC-SHA256 hex digest derived with key material held outside PostgreSQL.';
comment on column identity.external_identity_tokens.key_version is
  'External key version used to support bounded rotation without storing the key.';

-- Preserve the restricted-role model. Direct Supabase client roles remain denied
-- because schema usage/table privileges are not granted to them.
alter table identity.external_identity_tokens enable row level security;
alter table identity.external_identity_tokens force row level security;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'lifemate_edge_runtime') then
    grant select, insert, update, delete on identity.external_identity_tokens
      to lifemate_edge_runtime;
    drop policy if exists lifemate_edge_runtime_access
      on identity.external_identity_tokens;
    create policy lifemate_edge_runtime_access
      on identity.external_identity_tokens
      for all to lifemate_edge_runtime
      using (true) with check (true);
  end if;

  if exists (select 1 from pg_roles where rolname = 'lifemate_worker_runtime') then
    -- Account-deletion finalization must be able to purge the auth-link token.
    grant select, delete on identity.external_identity_tokens
      to lifemate_worker_runtime;
    drop policy if exists lifemate_worker_runtime_access
      on identity.external_identity_tokens;
    create policy lifemate_worker_runtime_access
      on identity.external_identity_tokens
      for all to lifemate_worker_runtime
      using (true) with check (true);
  end if;
end
$$;

-- Finalized accounts retain a minimal tombstone under retention-v2 instead of
-- deleting the account row. Purge opaque auth-link tokens at the same boundary
-- so a deleted account cannot continue to authenticate through this future path.
create or replace function identity.purge_external_identity_tokens_on_account_deleted()
returns trigger
language plpgsql
set search_path = pg_catalog, identity, pg_temp
as $$
begin
  if new.status = 'Deleted' and old.status is distinct from 'Deleted' then
    delete from identity.external_identity_tokens
    where account_id = new.id;
  end if;
  return new;
end
$$;

revoke all on function identity.purge_external_identity_tokens_on_account_deleted()
  from public;

drop trigger if exists trg_purge_external_identity_tokens_on_account_deleted
  on identity.accounts;
create trigger trg_purge_external_identity_tokens_on_account_deleted
after update of status on identity.accounts
for each row execute function identity.purge_external_identity_tokens_on_account_deleted();

-- Explicitly preserve direct-client denial if these Supabase roles exist.
do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists (select 1 from pg_roles where rolname = v_role) then
      execute format(
        'revoke all on identity.external_identity_tokens from %I',
        v_role
      );
    end if;
  end loop;
end
$$;
