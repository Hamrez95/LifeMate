create table if not exists pregnancy.observation_links (
  episode_id uuid not null references pregnancy.episodes(id) on delete cascade,
  observation_id uuid not null references lifemate.health_observations(id) on delete cascade,
  linked_by_account_id uuid references identity.accounts(id) on delete set null,
  created_at_utc timestamptz not null default now(),
  primary key (episode_id, observation_id),
  unique (observation_id)
);

create index if not exists ix_pregnancy_observation_links_episode_time
  on pregnancy.observation_links(episode_id, created_at_utc desc, observation_id);

create or replace function pregnancy.enforce_observation_link_subject()
returns trigger
language plpgsql
set search_path=pg_catalog,pregnancy,lifemate
as $$
declare
  episode_person uuid;
  observation_person uuid;
begin
  select mother_person_id into episode_person
  from pregnancy.episodes
  where id=new.episode_id;

  select person_id into observation_person
  from lifemate.health_observations
  where id=new.observation_id;

  if episode_person is null or observation_person is null or episode_person <> observation_person then
    raise exception 'pregnancy observation subject mismatch' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function pregnancy.enforce_observation_link_subject() from public;

drop trigger if exists trg_pregnancy_observation_link_subject on pregnancy.observation_links;
create trigger trg_pregnancy_observation_link_subject
before insert or update on pregnancy.observation_links
for each row execute function pregnancy.enforce_observation_link_subject();

alter table pregnancy.observation_links enable row level security;
alter table pregnancy.observation_links force row level security;
revoke all on pregnancy.observation_links from public;

do $$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if to_regrole(role_name) is not null then
      execute format('revoke all on pregnancy.observation_links from %I', role_name);
    end if;
  end loop;
end $$;

grant select,insert,update,delete on pregnancy.observation_links to lifemate_edge_runtime;
grant select on pregnancy.observation_links to lifemate_backup_reader;

create policy lifemate_edge_runtime_access
on pregnancy.observation_links
for all to lifemate_edge_runtime
using(true) with check(true);

comment on table pregnancy.observation_links is
  'Narrow pregnancy episode context for canonical lifemate.health_observations. Measurement values and units are never duplicated here.';
