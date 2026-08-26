-- Versioned recurrence for appointment/injection/checkup series.
-- Existing recurrence_* columns remain compatibility data for pre-#474 rows.
-- New rows write recurrence_rule and keep legacy columns at their safe defaults.

alter table lifemate.care_events
  add column if not exists recurrence_rule jsonb null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_rule_v2_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_rule_v2_check
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

create index if not exists ix_care_events_patient_unified_recurrence
  on lifemate.care_events(patient_user_id, scheduled_local_date)
  where status <> 'Cancelled' and recurrence_rule is not null;
