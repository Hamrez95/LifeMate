-- Reconcile local PostgreSQL CI with the production Supabase extension layout
-- and the canonical recurrence model where optional maxOccurrences may be null.
--
-- Safety: required recurrence shape and numeric bounds remain unchanged. A JSON
-- null is treated the same as an omitted optional maxOccurrences field.

create schema if not exists extensions;

do $$
declare
  v_schema text;
begin
  select n.nspname
    into v_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_schema is not null and v_schema <> 'extensions' then
    alter extension pgcrypto set schema extensions;
  end if;
end $$;

alter table lifemate.care_events
  drop constraint if exists care_events_recurrence_rule_v2_check;

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
        or recurrence_rule->'maxOccurrences' = 'null'::jsonb
        or (recurrence_rule->>'maxOccurrences')::integer between 1 and 10000
      )
    )
  );

alter table lifemate.treatment_plans
  drop constraint if exists treatment_plans_recurrence_rule_check;

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
        or recurrence_rule->'maxOccurrences' = 'null'::jsonb
        or (recurrence_rule->>'maxOccurrences')::integer between 1 and 10000
      )
    )
  );
