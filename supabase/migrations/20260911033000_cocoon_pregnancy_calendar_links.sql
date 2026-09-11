create table if not exists pregnancy.care_event_links (
  episode_id uuid not null references pregnancy.episodes(id) on delete cascade,
  care_event_id uuid not null references lifemate.care_events(id) on delete cascade,
  classification varchar(32) not null
    check (classification in (
      'prenatal','ultrasound','checkup','lab_test','injection','other'
    )),
  linked_by_account_id uuid references identity.accounts(id) on delete set null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  primary key (episode_id, care_event_id),
  unique (care_event_id)
);

create index if not exists ix_pregnancy_care_event_links_episode_time
  on pregnancy.care_event_links(episode_id, created_at_utc desc, care_event_id);

create or replace function pregnancy.enforce_care_event_link_subject()
returns trigger
language plpgsql
set search_path=pg_catalog,pregnancy,lifemate
as $$
declare
  episode_person uuid;
  event_person uuid;
begin
  select mother_person_id into episode_person
  from pregnancy.episodes
  where id=new.episode_id;

  select patient_person_id into event_person
  from lifemate.care_events
  where id=new.care_event_id;

  if episode_person is null or event_person is null or episode_person <> event_person then
    raise exception 'pregnancy care-event subject mismatch'
      using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function pregnancy.enforce_care_event_link_subject() from public;

drop trigger if exists trg_pregnancy_care_event_link_subject
  on pregnancy.care_event_links;
create trigger trg_pregnancy_care_event_link_subject
before insert or update on pregnancy.care_event_links
for each row execute function pregnancy.enforce_care_event_link_subject();

alter table pregnancy.care_event_links enable row level security;
alter table pregnancy.care_event_links force row level security;

revoke all on pregnancy.care_event_links from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on pregnancy.care_event_links from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on pregnancy.care_event_links from authenticated';
  end if;
  if to_regrole('service_role') is not null then
    execute 'revoke all on pregnancy.care_event_links from service_role';
  end if;
end $$;

grant select,insert,update,delete on pregnancy.care_event_links
  to lifemate_edge_runtime;
grant select on pregnancy.care_event_links to lifemate_backup_reader;

drop policy if exists lifemate_edge_runtime_access
  on pregnancy.care_event_links;
create policy lifemate_edge_runtime_access
on pregnancy.care_event_links
for all to lifemate_edge_runtime
using(true) with check(true);

comment on table pregnancy.care_event_links is
  'Narrow pregnancy-context association to canonical lifemate.care_events. No appointment/provider/date/status facts are copied here.';
