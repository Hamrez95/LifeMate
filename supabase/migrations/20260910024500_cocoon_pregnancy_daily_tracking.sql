create table if not exists pregnancy.daily_check_ins (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references pregnancy.episodes(id) on delete cascade,
  logged_local_date date not null,
  time_zone varchar(64) not null check (length(btrim(time_zone)) between 1 and 64),
  feeling varchar(16) not null
    check (feeling in ('comfortable','mixed','difficult')),
  energy varchar(16) not null
    check (energy in ('low','steady','high')),
  client_request_id uuid not null,
  recorded_by_account_id uuid references identity.accounts(id) on delete set null,
  version integer not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  unique (episode_id, client_request_id),
  unique (episode_id, logged_local_date)
);

create index if not exists ix_pregnancy_daily_check_ins_episode_date
  on pregnancy.daily_check_ins(episode_id, logged_local_date desc, id);

create table if not exists pregnancy.symptom_entries (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references pregnancy.episodes(id) on delete cascade,
  symptom_code varchar(64) not null
    check (symptom_code ~ '^[a-z][a-z0-9_]{1,63}$'),
  intensity varchar(16) not null
    check (intensity in ('mild','moderate','strong')),
  note varchar(400),
  observed_at_utc timestamptz not null,
  observed_local_date date not null,
  time_zone varchar(64) not null check (length(btrim(time_zone)) between 1 and 64),
  safety_signal varchar(40)
    check (
      safety_signal is null or safety_signal in (
        'heavy_bleeding',
        'loss_of_consciousness',
        'severe_breathing_difficulty',
        'severe_chest_pain'
      )
    ),
  safety_rule_set_version integer
    check (safety_rule_set_version is null or safety_rule_set_version >= 1),
  client_request_id uuid not null,
  recorded_by_account_id uuid references identity.accounts(id) on delete set null,
  version integer not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  unique (episode_id, client_request_id),
  constraint ck_pregnancy_symptom_note check (
    note is null or length(note) between 1 and 400
  ),
  constraint ck_pregnancy_symptom_safety_version check (
    (safety_signal is null) = (safety_rule_set_version is null)
  )
);

create index if not exists ix_pregnancy_symptom_entries_episode_time
  on pregnancy.symptom_entries(episode_id, observed_at_utc desc, id desc);
create index if not exists ix_pregnancy_symptom_entries_episode_date
  on pregnancy.symptom_entries(episode_id, observed_local_date desc, id desc);

alter table pregnancy.daily_check_ins enable row level security;
alter table pregnancy.daily_check_ins force row level security;
alter table pregnancy.symptom_entries enable row level security;
alter table pregnancy.symptom_entries force row level security;

revoke all on pregnancy.daily_check_ins, pregnancy.symptom_entries from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on pregnancy.daily_check_ins,pregnancy.symptom_entries from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on pregnancy.daily_check_ins,pregnancy.symptom_entries from authenticated';
  end if;
  if to_regrole('service_role') is not null then
    execute 'revoke all on pregnancy.daily_check_ins,pregnancy.symptom_entries from service_role';
  end if;
end $$;

grant select, insert, update, delete
  on pregnancy.daily_check_ins, pregnancy.symptom_entries
  to lifemate_edge_runtime;
grant select
  on pregnancy.daily_check_ins, pregnancy.symptom_entries
  to lifemate_backup_reader;

drop policy if exists lifemate_edge_runtime_access on pregnancy.daily_check_ins;
create policy lifemate_edge_runtime_access
  on pregnancy.daily_check_ins
  for all to lifemate_edge_runtime
  using (true) with check (true);

drop policy if exists lifemate_edge_runtime_access on pregnancy.symptom_entries;
create policy lifemate_edge_runtime_access
  on pregnancy.symptom_entries
  for all to lifemate_edge_runtime
  using (true) with check (true);

comment on table pregnancy.daily_check_ins is
  'Typed, pregnancy-episode-scoped daily wellbeing capture. Feeling is non-diagnostic mood/wellbeing state; raw values are PHI and must not enter ordinary analytics.';
comment on table pregnancy.symptom_entries is
  'Typed pregnancy symptom capture. Safety signal stores only the deterministic reviewed handoff code; it is not a diagnosis.';
