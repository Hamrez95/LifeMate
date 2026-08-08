-- Additive recurrence metadata for appointments and injections.
-- Existing rows remain non-recurring and no care-event data is rewritten.

alter table lifemate.care_events
  add column if not exists recurrence_unit varchar(16) not null default 'none',
  add column if not exists recurrence_interval integer not null default 1,
  add column if not exists recurrence_weekdays smallint[] not null default '{}',
  add column if not exists recurrence_end_date date null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_unit_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_unit_check
      check (recurrence_unit in ('none', 'day', 'week', 'month', 'year'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_interval_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_interval_check
      check (recurrence_interval between 1 and 365);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_weekdays_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_weekdays_check
      check (
        recurrence_weekdays <@ array[1,2,3,4,5,6,7]::smallint[]
        and cardinality(recurrence_weekdays) <= 7
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_end_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_end_check
      check (recurrence_end_date is null or recurrence_end_date >= scheduled_local_date);
  end if;
end $$;

create index if not exists ix_care_events_patient_recurrence_window
  on lifemate.care_events(patient_user_id, scheduled_local_date, recurrence_end_date)
  where status <> 'Cancelled';
