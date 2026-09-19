-- Keep canonical recurrence persistence compatible with normalized optional fields.
-- JSON null for maxOccurrences is semantically equivalent to the optional key
-- being absent; non-null values remain strictly bounded.

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
