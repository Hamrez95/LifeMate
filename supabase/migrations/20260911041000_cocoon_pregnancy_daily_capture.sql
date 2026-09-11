create table if not exists pregnancy.daily_check_ins (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references pregnancy.episodes(id) on delete restrict,
  mother_person_id uuid not null references core.persons(id) on delete restrict,
  observed_at_utc timestamptz not null,
  local_date date not null,
  time_zone varchar(64) not null,
  feeling varchar(16) not null check (feeling in ('comfortable','mixed','difficult')),
  energy varchar(16) not null check (energy in ('low','steady','high')),
  client_request_id uuid not null,
  recorded_by_account_id uuid not null references identity.accounts(id) on delete restrict,
  version integer not null default 1 check (version > 0),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  unique (episode_id, local_date),
  unique (mother_person_id, client_request_id)
);

create table if not exists pregnancy.symptom_reports (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references pregnancy.episodes(id) on delete restrict,
  mother_person_id uuid not null references core.persons(id) on delete restrict,
  observed_at_utc timestamptz not null,
  local_date date not null,
  time_zone varchar(64) not null,
  symptom_code varchar(64) not null check (
    symptom_code ~ '^[a-z0-9][a-z0-9._-]{1,63}$'
  ),
  intensity varchar(16) not null check (intensity in ('mild','moderate','strong')),
  note varchar(400),
  client_request_id uuid not null,
  recorded_by_account_id uuid not null references identity.accounts(id) on delete restrict,
  version integer not null default 1 check (version > 0),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  unique (mother_person_id, client_request_id)
);

create table if not exists pregnancy.mood_entries (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references pregnancy.episodes(id) on delete restrict,
  mother_person_id uuid not null references core.persons(id) on delete restrict,
  observed_at_utc timestamptz not null,
  local_date date not null,
  time_zone varchar(64) not null,
  mood_code varchar(16) not null check (
    mood_code in ('very_low','low','neutral','good','very_good')
  ),
  client_request_id uuid not null,
  recorded_by_account_id uuid not null references identity.accounts(id) on delete restrict,
  version integer not null default 1 check (version > 0),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  unique (mother_person_id, client_request_id)
);

create index if not exists ix_pregnancy_daily_check_ins_episode_date
  on pregnancy.daily_check_ins(episode_id, local_date desc, id desc);
create index if not exists ix_pregnancy_symptom_reports_episode_time
  on pregnancy.symptom_reports(episode_id, observed_at_utc desc, id desc);
create index if not exists ix_pregnancy_mood_entries_episode_time
  on pregnancy.mood_entries(episode_id, observed_at_utc desc, id desc);

create or replace function pregnancy.enforce_capture_episode_subject()
returns trigger
language plpgsql
set search_path=pg_catalog,pregnancy
as $$
begin
  if not exists (
    select 1 from pregnancy.episodes e
    where e.id=new.episode_id
      and e.mother_person_id=new.mother_person_id
  ) then
    raise exception 'pregnancy capture subject mismatch' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function pregnancy.enforce_capture_episode_subject() from public;

do $capture_triggers$
declare table_name text;
declare trigger_name text;
begin
  foreach table_name in array array['daily_check_ins','symptom_reports','mood_entries'] loop
    trigger_name := 'trg_' || table_name || '_episode_subject';
    execute format(
      'drop trigger if exists %I on pregnancy.%I',
      trigger_name,
      table_name
    );
    execute format(
      'create trigger %I before insert or update on pregnancy.%I for each row execute function pregnancy.enforce_capture_episode_subject()',
      trigger_name,
      table_name
    );
  end loop;
end
$capture_triggers$;

do $capture_security$
declare table_name text;
declare role_name text;
begin
  foreach table_name in array array['daily_check_ins','symptom_reports','mood_entries'] loop
    execute format('alter table pregnancy.%I enable row level security', table_name);
    execute format('alter table pregnancy.%I force row level security', table_name);
    execute format('revoke all on pregnancy.%I from public', table_name);

    foreach role_name in array array['anon','authenticated','service_role'] loop
      if to_regrole(role_name) is not null then
        execute format('revoke all on pregnancy.%I from %I', table_name, role_name);
      end if;
    end loop;

    execute format('grant select,insert,update,delete on pregnancy.%I to lifemate_edge_runtime', table_name);
    execute format('grant select on pregnancy.%I to lifemate_backup_reader', table_name);
    execute format(
      'create policy lifemate_edge_runtime_access on pregnancy.%I for all to lifemate_edge_runtime using(true) with check(true)',
      table_name
    );
  end loop;
end
$capture_security$;

comment on table pregnancy.daily_check_ins is
  'Typed owner pregnancy daily check-in. One logical check-in per episode/local date; client request UUID provides retry idempotency.';
comment on table pregnancy.symptom_reports is
  'Typed pregnancy symptom self-report. Structured code/intensity are non-diagnostic; free-text note is sensitive and is not an automated clinical classifier input.';
comment on table pregnancy.mood_entries is
  'Bounded non-diagnostic pregnancy mood self-report. It does not encode or infer a mental-health diagnosis.';
