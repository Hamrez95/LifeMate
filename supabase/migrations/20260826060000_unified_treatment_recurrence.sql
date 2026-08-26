-- Unified versioned recurrence metadata for Treatment Plans.
-- Existing weekly schedule rows remain authoritative when recurrence_rule is null.
-- Recurring plans use one treatment_schedules anchor row with day_of_week =
-- 'recurrence'; the existing occurrence uniqueness key therefore remains valid.

alter table lifemate.treatment_plans
  add column if not exists recurrence_rule jsonb null,
  add column if not exists recurrence_start_local_time time without time zone null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'treatment_plans_recurrence_pair_check'
      and conrelid = 'lifemate.treatment_plans'::regclass
  ) then
    alter table lifemate.treatment_plans
      add constraint treatment_plans_recurrence_pair_check
      check (
        (recurrence_rule is null and recurrence_start_local_time is null)
        or (recurrence_rule is not null and recurrence_start_local_time is not null)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'treatment_plans_recurrence_rule_check'
      and conrelid = 'lifemate.treatment_plans'::regclass
  ) then
    alter table lifemate.treatment_plans
      add constraint treatment_plans_recurrence_rule_check
      check (
        recurrence_rule is null
        or (
          jsonb_typeof(recurrence_rule) = 'object'
          and recurrence_rule @> '{"enabled":true}'::jsonb
          and (recurrence_rule->>'version')::integer between 1 and 1000
          and recurrence_rule->>'unit' in ('hour','day','week','month','year')
          and (recurrence_rule->>'interval')::integer between 1 and 8760
          and (
            not (recurrence_rule ? 'maxOccurrences')
            or (recurrence_rule->>'maxOccurrences')::integer between 1 and 10000
          )
        )
      );
  end if;
end $$;

create index if not exists ix_treatment_plans_patient_active_recurrence
  on lifemate.treatment_plans(patient_person_id, start_date)
  where status = 'Active' and recurrence_rule is not null;
