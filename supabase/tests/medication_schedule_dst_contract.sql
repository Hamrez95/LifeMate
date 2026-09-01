\set ON_ERROR_STOP on
begin;

do $$
declare
  spring_wall_hours numeric;
  spring_exact_hours numeric;
  spring_exact_local timestamp without time zone;
  fall_wall_hours numeric;
  fall_exact_hours numeric;
  fall_exact_local timestamp without time zone;
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'lifemate'
      and p.proname = 'enforce_exact_hourly_dose_elapsed'
  ) then
    raise exception 'exact-hour DST trigger function is missing';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'lifemate'
      and c.relname = 'dose_occurrences'
      and t.tgname = 'trg_00_enforce_exact_hourly_elapsed'
      and not t.tgisinternal
  ) then
    raise exception 'exact-hour DST trigger is missing';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'lifemate'
      and c.relname = 'medication_schedule_optimization_runs'
      and t.tgname = 'trg_reject_sleep_optimization_dst_transition'
      and not t.tgisinternal
  ) then
    raise exception 'sleep optimization DST fail-closed trigger is missing';
  end if;

  select
    extract(epoch from (
      (timestamp '2026-03-08 07:00' at time zone 'America/New_York')
      - (timestamp '2026-03-07 23:00' at time zone 'America/New_York')
    )) / 3600,
    extract(epoch from (
      ((timestamp '2026-03-07 23:00' at time zone 'America/New_York') + interval '8 hours')
      - (timestamp '2026-03-07 23:00' at time zone 'America/New_York')
    )) / 3600,
    ((timestamp '2026-03-07 23:00' at time zone 'America/New_York') + interval '8 hours')
      at time zone 'America/New_York'
  into spring_wall_hours, spring_exact_hours, spring_exact_local;

  if spring_wall_hours <> 7 then
    raise exception 'spring-forward control must demonstrate a 7-hour wall-clock elapsed gap, got %', spring_wall_hours;
  end if;
  if spring_exact_hours <> 8 or spring_exact_local <> timestamp '2026-03-08 08:00' then
    raise exception 'spring-forward exact q8h contract failed: elapsed %, local %', spring_exact_hours, spring_exact_local;
  end if;

  select
    extract(epoch from (
      (timestamp '2026-11-01 07:00' at time zone 'America/New_York')
      - (timestamp '2026-10-31 23:00' at time zone 'America/New_York')
    )) / 3600,
    extract(epoch from (
      ((timestamp '2026-10-31 23:00' at time zone 'America/New_York') + interval '8 hours')
      - (timestamp '2026-10-31 23:00' at time zone 'America/New_York')
    )) / 3600,
    ((timestamp '2026-10-31 23:00' at time zone 'America/New_York') + interval '8 hours')
      at time zone 'America/New_York'
  into fall_wall_hours, fall_exact_hours, fall_exact_local;

  if fall_wall_hours <> 9 then
    raise exception 'fall-back control must demonstrate a 9-hour wall-clock elapsed gap, got %', fall_wall_hours;
  end if;
  if fall_exact_hours <> 8 or fall_exact_local <> timestamp '2026-11-01 06:00' then
    raise exception 'fall-back exact q8h contract failed: elapsed %, local %', fall_exact_hours, fall_exact_local;
  end if;
end $$;

rollback;
