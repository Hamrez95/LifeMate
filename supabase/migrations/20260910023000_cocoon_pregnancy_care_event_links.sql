create table if not exists pregnancy.care_event_links (
  episode_id uuid not null
    references pregnancy.episodes(id) on delete cascade,
  care_event_id uuid not null
    references lifemate.care_events(id) on delete cascade,
  linked_by_account_id uuid
    references identity.accounts(id) on delete set null,
  idempotency_key_hash char(64) not null
    check (idempotency_key_hash ~ '^[0-9a-f]{64}$'),
  created_at_utc timestamptz not null default now(),
  primary key (episode_id, care_event_id),
  unique (care_event_id),
  unique (episode_id, idempotency_key_hash)
);

create index if not exists ix_pregnancy_care_event_links_episode_time
  on pregnancy.care_event_links(episode_id, created_at_utc desc, care_event_id);

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

grant select, insert, update, delete
  on pregnancy.care_event_links to lifemate_edge_runtime;
grant select
  on pregnancy.care_event_links to lifemate_backup_reader;

drop policy if exists lifemate_edge_runtime_access
  on pregnancy.care_event_links;
create policy lifemate_edge_runtime_access
  on pregnancy.care_event_links
  for all to lifemate_edge_runtime
  using (true) with check (true);

comment on table pregnancy.care_event_links is
  'Sensitive pregnancy-episode context for canonical lifemate.care_events. Appointment facts, recurrence, reminders and status remain owned by lifemate.care_events.';
