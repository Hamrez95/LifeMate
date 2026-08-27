-- #497: reviewed quasi-identifier transforms. Unknown transform keys are rejected
-- instead of being stored and silently ignored. Exact home-region labels are not
-- an allowed export mode; datasets may omit region or generalize it to country.

create or replace function analytics.research_quasi_rules_valid(p_rules jsonb)
returns boolean
language sql
immutable
set search_path=pg_catalog,pg_temp
as $$
  select case
    when p_rules is null then true
    when jsonb_typeof(p_rules) <> 'object' then false
    when exists(
      select 1 from jsonb_object_keys(p_rules) key
      where key not in ('homeRegionMode')
    ) then false
    when p_rules ? 'homeRegionMode' and p_rules->>'homeRegionMode' not in ('omit','country') then false
    else true
  end
$$;

revoke all on function analytics.research_quasi_rules_valid(jsonb) from public;

alter table analytics.dataset_privacy_policies
  drop constraint if exists ck_dataset_privacy_quasi_rules;
alter table analytics.dataset_privacy_policies
  add constraint ck_dataset_privacy_quasi_rules
  check (analytics.research_quasi_rules_valid(quasi_identifier_rules));
