-- #497: function-only Founder read projection for Research Studio consumers.

-- CREATE OR REPLACE cannot change an existing function's OUT/RETURNS TABLE row type.
-- This migration intentionally evolves the read contract, so make reruns explicit and safe.
drop function if exists analytics.list_research_datasets(uuid);

create function analytics.list_research_datasets(p_actor uuid)
returns table(
  dataset_id uuid,
  name varchar,
  purpose varchar,
  source_category varchar,
  filter_json jsonb,
  dataset_version integer,
  status varchar,
  privacy_policy_version integer,
  age_bucket_years smallint,
  minimum_cohort_size integer,
  small_cell_threshold integer,
  quasi_identifier_rules jsonb,
  row_mode varchar,
  updated_at_utc timestamptz
)
language plpgsql
stable
security definer
set search_path=analytics,admin,pg_temp
as $$
begin
  if not admin.account_is_active_founder(p_actor) then
    raise exception using errcode='42501',message='research_founder_required';
  end if;
  return query
  select d.id,d.name,d.purpose,d.source_category,d.filter_json,d.version,d.status,
         p.policy_version,p.age_bucket_years,p.minimum_cohort_size,p.small_cell_threshold,
         p.quasi_identifier_rules,p.row_mode,greatest(d.updated_at_utc,p.updated_at_utc)
  from analytics.dataset_definitions d
  join analytics.dataset_privacy_policies p on p.dataset_id=d.id
  order by d.updated_at_utc desc,d.id;
end $$;

revoke all on function analytics.list_research_datasets(uuid) from public;
do $$ begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function analytics.list_research_datasets(uuid) to lifemate_admin_runtime;
  end if;
end $$;
