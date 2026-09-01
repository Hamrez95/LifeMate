-- Medication timing DST correctness hardening.
--
-- Hour-based medication recurrence is an elapsed-time contract. The original
-- local anchor is converted through the plan IANA zone once; subsequent hourly
-- occurrences remain exactly N elapsed hours apart. Daily/weekly/monthly/yearly
-- recurrence keeps its existing wall-clock behavior.
--
-- Sleep-aware optimization currently reasons about local wall-clock candidates.
-- Until that optimizer receives a fully timezone-aware candidate timeline, a
-- proposal whose bounded horizon crosses a DST offset transition fails closed
-- and leaves the exact canonical schedule unchanged.

create or replace function lifemate.enforce_exact_hourly_dose_elapsed()
returns trigger
language plpgsql
set search_path = pg_catalog, lifemate
as $$
declare
  v_plan record;
  v_rule jsonb;
  v_interval_hours integer;
  v_start_local timestamp without time zone;
  v_candidate_local timestamp without time zone;
  v_occurrence_index numeric;
  v_exact_utc timestamp with time zone;
  v_exact_local timestamp without time zone;
begin
  if new.status <> 'Scheduled' then
    return new;
  end if;

  select p.start_date,
         p.time_zone,
         p.recurrence_rule,
         p.recurrence_start_local_time
    into v_plan
  from lifemate.treatment_plans p
  where p.id = new.treatment_plan_id
    and p.patient_person_id = new.patient_person_id
  limit 1;

  if not found
     or v_plan.recurrence_rule is null
     or v_plan.recurrence_start_local_time is null then
    return new;
  end if;

  v_rule := v_plan.recurrence_rule::jsonb;
  if coalesce(v_rule ->> 'enabled', 'false') <> 'true'
     or lower(coalesce(v_rule ->> 'unit', '')) <> 'hour' then
    return new;
  end if;

  begin
    v_interval_hours := (v_rule ->> 'interval')::integer;
  exception when others then
    return new;
  end;
  if v_interval_hours is null or v_interval_hours < 1 then
    return new;
  end if;

  v_start_local := v_plan.start_date::timestamp
    + v_plan.recurrence_start_local_time;
  v_candidate_local := new.scheduled_local_date::timestamp
    + new.scheduled_local_time;

  v_occurrence_index :=
    extract(epoch from (v_candidate_local - v_start_local))
    / (v_interval_hours * 3600.0);

  -- Only normalize rows produced by the canonical hourly recurrence expander.
  -- Flexible overrides intentionally are not exact multiples of this identity.
  if v_occurrence_index < 0
     or abs(v_occurrence_index - round(v_occurrence_index)) > 0.000001 then
    return new;
  end if;

  v_exact_utc :=
    (v_start_local at time zone v_plan.time_zone)
    + ((round(v_occurrence_index)::bigint * v_interval_hours)
       * interval '1 hour');
  v_exact_local := v_exact_utc at time zone v_plan.time_zone;

  new.scheduled_at_utc := v_exact_utc;
  new.scheduled_local_date := v_exact_local::date;
  new.scheduled_local_time := v_exact_local::time;
  new.time_zone := v_plan.time_zone;
  return new;
end;
$$;

revoke all on function lifemate.enforce_exact_hourly_dose_elapsed() from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on function lifemate.enforce_exact_hourly_dose_elapsed() from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on function lifemate.enforce_exact_hourly_dose_elapsed() from authenticated';
  end if;
end $$;

-- PostgreSQL executes triggers of the same kind in name order. This trigger is
-- intentionally before trg_apply_active_dose_occurrence_override: outside a DST
-- transition the original local identity is unchanged, while DST-spanning sleep
-- proposals are rejected below before they can become Applied.
drop trigger if exists trg_00_enforce_exact_hourly_elapsed
  on lifemate.dose_occurrences;
create trigger trg_00_enforce_exact_hourly_elapsed
before insert on lifemate.dose_occurrences
for each row execute function lifemate.enforce_exact_hourly_dose_elapsed();

create or replace function lifemate.reject_sleep_optimization_dst_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, lifemate
as $$
begin
  if new.mode not in ('strict_anchor_shift', 'flexible_interval')
     or new.status <> 'Previewed' then
    return new;
  end if;

  if exists (
    select 1
    from lifemate.treatment_plans p
    where p.patient_person_id = new.owner_person_id
      and p.status = 'Active'
      and p.recurrence_rule is not null
      and coalesce(p.recurrence_rule::jsonb ->> 'enabled', 'false') = 'true'
      and lower(coalesce(p.recurrence_rule::jsonb ->> 'unit', '')) = 'hour'
      and p.start_date <= new.effective_until_local_date
      and (p.end_date is null or p.end_date >= new.effective_from_local_date)
      and (
        (((new.effective_from_local_date + time '12:00') at time zone p.time_zone)
          - ((new.effective_from_local_date + time '12:00') at time zone 'UTC'))
        is distinct from
        (((new.effective_until_local_date + time '12:00') at time zone p.time_zone)
          - ((new.effective_until_local_date + time '12:00') at time zone 'UTC'))
      )
  ) then
    raise exception
      'sleep optimization range crosses a DST transition; exact schedule remains unchanged'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

revoke all on function lifemate.reject_sleep_optimization_dst_transition() from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on function lifemate.reject_sleep_optimization_dst_transition() from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on function lifemate.reject_sleep_optimization_dst_transition() from authenticated';
  end if;
end $$;

drop trigger if exists trg_reject_sleep_optimization_dst_transition
  on lifemate.medication_schedule_optimization_runs;
create trigger trg_reject_sleep_optimization_dst_transition
before insert on lifemate.medication_schedule_optimization_runs
for each row execute function lifemate.reject_sleep_optimization_dst_transition();

-- Repair only untouched future Scheduled rows. Historical adherence remains
-- immutable. Applied flexible overrides are excluded explicitly.
with candidates as (
  select o.id,
         p.start_date,
         p.time_zone,
         p.recurrence_start_local_time,
         (p.recurrence_rule::jsonb ->> 'interval')::integer as interval_hours,
         (o.scheduled_local_date::timestamp + o.scheduled_local_time) as candidate_local,
         (p.start_date::timestamp + p.recurrence_start_local_time) as start_local
  from lifemate.dose_occurrences o
  join lifemate.treatment_plans p
    on p.id = o.treatment_plan_id
   and p.patient_person_id = o.patient_person_id
  where o.status = 'Scheduled'
    and o.scheduled_at_utc > now()
    and p.recurrence_rule is not null
    and p.recurrence_start_local_time is not null
    and coalesce(p.recurrence_rule::jsonb ->> 'enabled', 'false') = 'true'
    and lower(coalesce(p.recurrence_rule::jsonb ->> 'unit', '')) = 'hour'
    and (p.recurrence_rule::jsonb ->> 'interval') ~ '^[1-9][0-9]*$'
    and not exists (
      select 1
      from lifemate.dose_occurrence_overrides ov
      join lifemate.medication_schedule_optimization_runs r on r.id = ov.run_id
      where ov.treatment_plan_id = o.treatment_plan_id
        and ov.owner_person_id = o.patient_person_id
        and ov.replacement_local_date = o.scheduled_local_date
        and ov.replacement_local_time = o.scheduled_local_time
        and ov.status = 'Active'
        and r.status = 'Applied'
        and r.mode = 'flexible_interval'
    )
), normalized as (
  select c.*,
         extract(epoch from (c.candidate_local - c.start_local))
           / (c.interval_hours * 3600.0) as occurrence_index
  from candidates c
), repaired as (
  select n.id,
         ((n.start_local at time zone n.time_zone)
           + ((round(n.occurrence_index)::bigint * n.interval_hours)
             * interval '1 hour')) as exact_utc,
         (((n.start_local at time zone n.time_zone)
           + ((round(n.occurrence_index)::bigint * n.interval_hours)
             * interval '1 hour')) at time zone n.time_zone) as exact_local
  from normalized n
  where n.occurrence_index >= 0
    and abs(n.occurrence_index - round(n.occurrence_index)) <= 0.000001
)
update lifemate.dose_occurrences o
set scheduled_at_utc = r.exact_utc,
    scheduled_local_date = r.exact_local::date,
    scheduled_local_time = r.exact_local::time,
    version = o.version + 1,
    updated_at_utc = now()
from repaired r
where o.id = r.id
  and (
    o.scheduled_at_utc is distinct from r.exact_utc
    or o.scheduled_local_date is distinct from r.exact_local::date
    or o.scheduled_local_time is distinct from r.exact_local::time
  );

comment on function lifemate.enforce_exact_hourly_dose_elapsed() is
  'Keeps hour-based medication recurrence at exact elapsed intervals across DST while retaining an IANA-zone local representation.';
comment on function lifemate.reject_sleep_optimization_dst_transition() is
  'Fail-closed V1 guard: sleep optimization is not previewed across a DST offset transition until the optimizer consumes the canonical timezone-aware timeline.';
