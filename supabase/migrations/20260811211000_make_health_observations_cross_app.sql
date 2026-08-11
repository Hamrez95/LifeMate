-- Keep health data as a LifeMate ecosystem domain, not a WellMate-owned silo.
-- Person is the canonical data subject. Account is only the actor that recorded
-- the observation, and source_application identifies the LifeMate app that
-- captured it (WellMate today, FitMate or other apps later).

alter table lifemate.health_observations
  add column if not exists recorded_by_account_id uuid,
  add column if not exists source_application_id uuid;

-- Existing manual observations were created by the signed-in WellMate user.
update lifemate.health_observations
set recorded_by_account_id = owner_user_id
where recorded_by_account_id is null
  and owner_user_id is not null;

update lifemate.health_observations h
set source_application_id = a.id
from ecosystem.applications a
where h.source_application_id is null
  and a.code = 'wellmate';

-- The legacy owner_user_id column remains for compatibility with the currently
-- deployed API, but it is no longer canonical ownership and must not cascade
-- person-owned health history when an account is removed.
alter table lifemate.health_observations
  drop constraint if exists health_observations_owner_user_id_fkey;

alter table lifemate.health_observations
  alter column owner_user_id drop not null;

alter table lifemate.health_observations
  add constraint health_observations_owner_user_id_fkey
  foreign key (owner_user_id)
  references lifemate.app_users(id)
  on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'fk_health_observations_recorded_by_account'
  ) then
    alter table lifemate.health_observations
      add constraint fk_health_observations_recorded_by_account
      foreign key (recorded_by_account_id)
      references identity.accounts(id)
      on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'fk_health_observations_source_application'
  ) then
    alter table lifemate.health_observations
      add constraint fk_health_observations_source_application
      foreign key (source_application_id)
      references ecosystem.applications(id)
      on delete restrict;
  end if;
end
$$;

-- Rollout compatibility: the production API that existed before this migration
-- did not send the two new columns. Keep that writer safe while the new API is
-- deployed by deriving provenance for legacy WellMate inserts. New clients set
-- both columns explicitly, so this trigger becomes a no-op for them.
create or replace function lifemate.populate_health_observation_provenance()
returns trigger
language plpgsql
as $$
declare
  v_application_code text;
begin
  if new.recorded_by_account_id is null and new.owner_user_id is not null then
    new.recorded_by_account_id := new.owner_user_id;
  end if;

  if new.source_application_id is null then
    v_application_code := lower(coalesce(nullif(btrim(new.source_provider), ''), 'wellmate'));

    select id
      into new.source_application_id
    from ecosystem.applications
    where code = v_application_code
      and status = 'Active'
    limit 1;

    -- The only legacy writer at rollout is WellMate. If its historical provider
    -- label does not exactly match the application code, preserve availability
    -- by resolving the registered WellMate application explicitly.
    if new.source_application_id is null and new.owner_user_id is not null then
      select id
        into new.source_application_id
      from ecosystem.applications
      where code = 'wellmate'
        and status = 'Active'
      limit 1;
    end if;
  end if;

  return new;
end
$$;

drop trigger if exists trg_populate_health_observation_provenance
  on lifemate.health_observations;
create trigger trg_populate_health_observation_provenance
before insert on lifemate.health_observations
for each row
execute function lifemate.populate_health_observation_provenance();

-- Every observation entering the LifeMate health domain must retain which
-- ecosystem application captured it. External/device provider provenance stays
-- separately represented by source_category/source_provider. The compatibility
-- trigger above ensures the old production writer still satisfies this rule.
alter table lifemate.health_observations
  alter column source_application_id set not null;

-- Idempotency belongs to the Person + source application boundary, not to a
-- legacy WellMate account column. This prevents future apps from needing their
-- own health tables while still isolating request identities per application.
drop index if exists lifemate.ux_health_observations_owner_request;

create unique index if not exists ux_health_observations_person_app_request
  on lifemate.health_observations(person_id, source_application_id, client_request_id);

create index if not exists ix_health_observations_recorded_by_account
  on lifemate.health_observations(recorded_by_account_id, observed_at_utc desc)
  where recorded_by_account_id is not null;

create index if not exists ix_health_observations_source_application
  on lifemate.health_observations(source_application_id, observed_at_utc desc);

insert into security.scope_catalog(scope, domain, sensitivity, description) values
('health.observations.read','health','HEALTH','Read person-owned health observations shared across LifeMate applications'),
('health.observations.write','health','HEALTH','Create or manage person-owned health observations through an authorized LifeMate application')
on conflict (scope) do update set
  domain=excluded.domain,
  sensitivity=excluded.sensitivity,
  description=excluded.description;

comment on column lifemate.health_observations.owner_user_id is
  'Legacy compatibility actor/account column. Canonical ownership is person_id; new code should use recorded_by_account_id for actor provenance.';
comment on column lifemate.health_observations.recorded_by_account_id is
  'Account that recorded/imported the observation when applicable. Nullable so account lifecycle never destroys Person-owned health history.';
comment on column lifemate.health_observations.source_application_id is
  'LifeMate ecosystem application that captured the observation. Enables WellMate, FitMate and future apps to share one canonical Person health history.';
comment on column lifemate.health_observations.source_provider is
  'Provider inside the source application (for example wellmate manual input, HealthConnect, a wearable provider, or a partner integration).';
