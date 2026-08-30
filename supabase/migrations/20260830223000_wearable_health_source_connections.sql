begin;

create table if not exists lifemate.health_source_connections (
  id uuid primary key default gen_random_uuid(),
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  account_id uuid not null references identity.accounts(id) on delete cascade,
  platform character varying(24) not null,
  source_provider character varying(64) not null,
  connection_status character varying(24) not null default 'disconnected',
  permission_state character varying(24) not null default 'not_requested',
  enabled_measurements jsonb not null default '[]'::jsonb,
  sync_cursor_hash character varying(128),
  last_sync_started_at_utc timestamptz,
  last_sync_completed_at_utc timestamptz,
  last_sync_status character varying(24),
  disconnected_at_utc timestamptz,
  version integer not null default 1,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint ck_health_source_platform check (
    platform in ('android_health_connect','ios_healthkit')
  ),
  constraint ck_health_source_connection_status check (
    connection_status in ('connected','disconnected','unsupported','permission_denied')
  ),
  constraint ck_health_source_permission_state check (
    permission_state in ('not_requested','granted','denied','revoked','unsupported')
  ),
  constraint ck_health_source_measurements_array check (
    jsonb_typeof(enabled_measurements)='array'
    and jsonb_array_length(enabled_measurements) <= 32
  ),
  constraint ck_health_source_version check (version >= 1),
  constraint ck_health_source_sync_status check (
    last_sync_status is null or last_sync_status in ('success','partial','failed','no_data')
  )
);

create unique index if not exists ux_health_source_connection_person_platform_provider
  on lifemate.health_source_connections(owner_person_id, platform, source_provider);
create index if not exists ix_health_source_connection_account
  on lifemate.health_source_connections(account_id, updated_at_utc desc);

alter table lifemate.health_source_connections enable row level security;
alter table lifemate.health_source_connections force row level security;
revoke all on table lifemate.health_source_connections from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on table lifemate.health_source_connections from %I', v_role);
    end if;
  end loop;
end $$;

comment on table lifemate.health_source_connections is
  'Person-scoped OS health aggregation connection state. Measurements continue to use canonical lifemate.health_observations with source provenance; no vendor-specific health schema is created.';
comment on column lifemate.health_source_connections.enabled_measurements is
  'Explicitly user-authorized canonical measurement categories only.';
comment on column lifemate.health_source_connections.sync_cursor_hash is
  'Opaque hashed sync cursor/idempotency metadata; never raw provider token or credential.';

commit;