-- Keep plain-Postgres CI aligned with Supabase's pgcrypto schema placement and
-- allow normalized recurrence rules to persist optional null fields without
-- weakening the recurrence bounds or required shape.

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

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'care_events_recurrence_rule_v2_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      drop constraint care_events_recurrence_rule_v2_check;
  end if;

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
end $$;
