create table if not exists lifemate.health_observations (
    id uuid primary key,
    owner_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    person_id uuid not null references core.persons(id) on delete cascade,
    client_request_id uuid not null,
    observation_type varchar(40) not null,
    value_primary numeric(12,3),
    value_secondary numeric(12,3),
    unit_primary varchar(24),
    unit_secondary varchar(24),
    note varchar(500),
    observed_at_utc timestamptz not null,
    observed_local_date date not null,
    time_zone varchar(64) not null,
    source_category varchar(40) not null references analytics.source_policies(source_category),
    source_provider varchar(80) not null,
    source_external_id varchar(180),
    metadata_json jsonb not null default '{}'::jsonb,
    version integer not null default 1 check (version > 0),
    created_at_utc timestamptz not null default now(),
    updated_at_utc timestamptz not null default now(),
    constraint health_observations_type_check check (
      observation_type in (
        'weight', 'height', 'blood_pressure', 'heart_rate',
        'blood_glucose', 'oxygen_saturation', 'body_temperature',
        'sleep_duration', 'note'
      )
    ),
    constraint health_observations_value_check check (
      (observation_type = 'weight' and value_primary between 1 and 500 and value_secondary is null)
      or (observation_type = 'height' and value_primary between 30 and 250 and value_secondary is null)
      or (observation_type = 'blood_pressure' and value_primary between 40 and 300 and value_secondary between 20 and 200 and value_primary > value_secondary)
      or (observation_type = 'heart_rate' and value_primary between 20 and 300 and value_secondary is null)
      or (observation_type = 'blood_glucose' and value_primary between 20 and 1000 and value_secondary is null)
      or (observation_type = 'oxygen_saturation' and value_primary between 50 and 100 and value_secondary is null)
      or (observation_type = 'body_temperature' and value_primary between 25 and 45 and value_secondary is null)
      or (observation_type = 'sleep_duration' and value_primary between 0 and 24 and value_secondary is null)
      or (observation_type = 'note' and value_primary is null and value_secondary is null and note is not null and btrim(note) <> '')
    )
);

create unique index if not exists ux_health_observations_owner_request
  on lifemate.health_observations(owner_user_id, client_request_id);

create unique index if not exists ux_health_observations_source_external
  on lifemate.health_observations(person_id, source_category, source_external_id)
  where source_external_id is not null;

create index if not exists ix_health_observations_person_observed
  on lifemate.health_observations(person_id, observed_at_utc desc);

create index if not exists ix_health_observations_person_type_observed
  on lifemate.health_observations(person_id, observation_type, observed_at_utc desc);

create index if not exists ix_health_observations_person_local_date
  on lifemate.health_observations(person_id, observed_local_date desc, observed_at_utc desc);

alter table lifemate.health_observations enable row level security;
revoke all on table lifemate.health_observations from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on table lifemate.health_observations from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on table lifemate.health_observations from authenticated';
  end if;
end
$$;

comment on table lifemate.health_observations is
  'Canonical person-owned health observations. Manual and future device/provider measurements share one provenance-aware event model.';
comment on column lifemate.health_observations.person_id is
  'Canonical human/data-subject owner used to correlate health observations with treatment and care domains.';
comment on column lifemate.health_observations.source_category is
  'Must match analytics.source_policies. HealthConnect and device-sensor sources remain hard-blocked from secondary commercial export.';
