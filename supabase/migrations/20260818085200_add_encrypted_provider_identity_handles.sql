-- #354 / #217: provider-control operations (session revoke / hard Auth delete)
-- need a recoverable external provider handle before raw auth subjects can be
-- retired. Store authenticated ciphertext only; the decryption key remains an
-- external API/Worker runtime secret and is never persisted in PostgreSQL.

create table if not exists identity.provider_identity_handles (
  account_id uuid not null references identity.accounts(id) on delete cascade,
  provider character varying(80) not null,
  issuer character varying(255) not null,
  ciphertext_b64 text not null,
  nonce_b64 character varying(64) not null,
  key_version smallint not null,
  status character varying(24) not null default 'Active',
  created_at_utc timestamp with time zone not null default now(),
  updated_at_utc timestamp with time zone not null default now(),
  primary key(account_id,provider,issuer),
  constraint ck_provider_identity_handle_provider_nonempty
    check(length(btrim(provider)) between 1 and 80),
  constraint ck_provider_identity_handle_issuer_nonempty
    check(length(btrim(issuer)) between 1 and 255),
  constraint ck_provider_identity_handle_ciphertext_b64
    check(length(ciphertext_b64) between 24 and 5500),
  constraint ck_provider_identity_handle_nonce_b64
    check(length(nonce_b64) between 16 and 32),
  constraint ck_provider_identity_handle_key_version
    check(key_version between 1 and 32767),
  constraint ck_provider_identity_handle_status
    check(status in ('Active','Disabled'))
);

create index if not exists ix_provider_identity_handles_status
  on identity.provider_identity_handles(status,account_id);

comment on table identity.provider_identity_handles is
  'Externally keyed AES-GCM provider handles. Ciphertext is useless to a DB-only attacker without the runtime key; raw provider subjects are forbidden.';
comment on column identity.provider_identity_handles.ciphertext_b64 is
  'AES-GCM ciphertext including authentication tag; never plaintext provider/Auth subject.';
comment on column identity.provider_identity_handles.nonce_b64 is
  'Per-envelope 96-bit AES-GCM nonce, base64 encoded; not secret.';
comment on column identity.provider_identity_handles.key_version is
  'External provider-handle envelope key version; key material is never stored in PostgreSQL.';

alter table identity.provider_identity_handles enable row level security;
alter table identity.provider_identity_handles force row level security;
revoke all on identity.provider_identity_handles from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format(
        'revoke all on identity.provider_identity_handles from %I',
        v_role
      );
    end if;
  end loop;

  if exists(select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant select,insert,update on identity.provider_identity_handles
      to lifemate_edge_runtime;

    drop policy if exists lifemate_edge_runtime_provider_handle_select
      on identity.provider_identity_handles;
    create policy lifemate_edge_runtime_provider_handle_select
      on identity.provider_identity_handles
      for select to lifemate_edge_runtime
      using (true);

    drop policy if exists lifemate_edge_runtime_provider_handle_insert
      on identity.provider_identity_handles;
    create policy lifemate_edge_runtime_provider_handle_insert
      on identity.provider_identity_handles
      for insert to lifemate_edge_runtime
      with check (true);

    drop policy if exists lifemate_edge_runtime_provider_handle_update
      on identity.provider_identity_handles;
    create policy lifemate_edge_runtime_provider_handle_update
      on identity.provider_identity_handles
      for update to lifemate_edge_runtime
      using (true) with check (true);
  end if;

  if exists(select 1 from pg_roles where rolname='lifemate_worker_runtime') then
    grant select on identity.provider_identity_handles to lifemate_worker_runtime;

    drop policy if exists lifemate_worker_runtime_provider_handle_select
      on identity.provider_identity_handles;
    create policy lifemate_worker_runtime_provider_handle_select
      on identity.provider_identity_handles
      for select to lifemate_worker_runtime
      using (true);
  end if;
end
$$;
