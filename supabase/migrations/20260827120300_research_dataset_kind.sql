-- #497: never infer the source domain from arbitrary filter JSON. Each dataset
-- kind receives its own reviewed adapter/allow-list.

alter table analytics.dataset_definitions
  add column if not exists dataset_kind character varying(48) not null default 'HealthObservationAggregate';

alter table analytics.dataset_definitions
  drop constraint if exists ck_dataset_definitions_kind;
alter table analytics.dataset_definitions
  add constraint ck_dataset_definitions_kind
  check (dataset_kind in (
    'HealthObservationAggregate',
    'DoseAdherenceAggregate',
    'TreatmentAggregate',
    'WomenCycleAggregate'
  ));

-- Match the exact signature created below so reruns replace, rather than collide with,
-- the dataset-kind-aware contract.
drop function if exists analytics.create_research_dataset(
  uuid,varchar,varchar,varchar,varchar,jsonb,smallint,integer,integer,jsonb,varchar,uuid
);

create function analytics.create_research_dataset(
  p_actor uuid,p_name varchar,p_dataset_kind varchar,p_purpose varchar,p_source_category varchar,p_filter jsonb,
  p_age_bucket_years smallint,p_minimum_cohort_size integer,p_small_cell_threshold integer,
  p_quasi_identifier_rules jsonb,p_row_mode varchar,p_correlation_id uuid
) returns uuid
language plpgsql security definer set search_path=analytics,admin,pg_temp as $$
declare v_id uuid; v_policy_min integer; v_research_allowed boolean;
begin
  if p_correlation_id is null then raise exception using errcode='22023',message='research_correlation_required'; end if;
  if not admin.account_is_active_founder(p_actor) then raise exception using errcode='42501',message='research_founder_required'; end if;
  if p_dataset_kind not in ('HealthObservationAggregate','DoseAdherenceAggregate','TreatmentAggregate','WomenCycleAggregate') then
    raise exception using errcode='22023',message='research_dataset_kind_invalid';
  end if;
  select minimum_cohort_size into v_policy_min from analytics.export_policies where purpose=p_purpose;
  if v_policy_min is null then raise exception using errcode='42501',message='research_export_policy_unknown'; end if;
  select research_allowed into v_research_allowed from analytics.source_policies where source_category=p_source_category;
  if v_research_allowed is distinct from true then raise exception using errcode='42501',message='research_source_not_allowed'; end if;
  if p_minimum_cohort_size < greatest(v_policy_min,5) or p_small_cell_threshold < 5 or p_small_cell_threshold > p_minimum_cohort_size then
    raise exception using errcode='22023',message='research_privacy_threshold_invalid';
  end if;
  if p_row_mode not in ('Aggregate','Pseudonymous') then raise exception using errcode='22023',message='research_row_mode_invalid'; end if;
  if jsonb_typeof(coalesce(p_filter,'{}'::jsonb)) <> 'object'
     or octet_length(coalesce(p_filter,'{}'::jsonb)::text)>16000
     or analytics.research_json_contains_direct_identifier(coalesce(p_filter,'{}'::jsonb)) then
    raise exception using errcode='22023',message='research_filter_invalid';
  end if;
  if jsonb_typeof(coalesce(p_quasi_identifier_rules,'{}'::jsonb)) <> 'object'
     or octet_length(coalesce(p_quasi_identifier_rules,'{}'::jsonb)::text)>16000
     or analytics.research_json_contains_direct_identifier(coalesce(p_quasi_identifier_rules,'{}'::jsonb)) then
    raise exception using errcode='22023',message='research_transform_invalid';
  end if;
  insert into analytics.dataset_definitions(name,dataset_kind,purpose,source_category,filter_json,created_by_account_id)
  values(trim(p_name),p_dataset_kind,p_purpose,p_source_category,coalesce(p_filter,'{}'::jsonb),p_actor) returning id into v_id;
  insert into analytics.dataset_privacy_policies(dataset_id,age_bucket_years,minimum_cohort_size,small_cell_threshold,quasi_identifier_rules,row_mode,updated_by_account_id)
  values(v_id,p_age_bucket_years,p_minimum_cohort_size,p_small_cell_threshold,coalesce(p_quasi_identifier_rules,'{}'::jsonb),p_row_mode,p_actor);
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,metadata_json)
  values(p_actor,'research.dataset.created','research_dataset',v_id::text,'Succeeded',p_correlation_id,jsonb_build_object('datasetKind',p_dataset_kind,'purpose',p_purpose,'sourceCategory',p_source_category,'rowMode',p_row_mode,'minimumCohortSize',p_minimum_cohort_size,'smallCellThreshold',p_small_cell_threshold));
  return v_id;
end $$;

revoke all on function analytics.create_research_dataset(uuid,varchar,varchar,varchar,varchar,jsonb,smallint,integer,integer,jsonb,varchar,uuid) from public;
do $$ begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function analytics.create_research_dataset(uuid,varchar,varchar,varchar,varchar,jsonb,smallint,integer,integer,jsonb,varchar,uuid) to lifemate_admin_runtime;
  end if;
end $$;

drop function if exists analytics.list_research_datasets(uuid);
create function analytics.list_research_datasets(p_actor uuid)
returns table(
  dataset_id uuid,
  name varchar,
  dataset_kind varchar,
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
  select d.id,d.name,d.dataset_kind,d.purpose,d.source_category,d.filter_json,d.version,d.status,
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
