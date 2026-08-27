-- #497: first explicit source adapter. No generic SQL, notes, metadata, provider
-- identifiers or subject identifiers enter the projection.

create or replace function analytics.preview_research_health_observations(
  p_actor uuid,
  p_dataset_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path=analytics,admin,consent,core,lifemate,pg_temp
as $$
declare
  v_dataset analytics.dataset_definitions%rowtype;
  v_policy analytics.dataset_privacy_policies%rowtype;
  v_export_policy analytics.export_policies%rowtype;
  v_cohort integer;
  v_cells jsonb;
begin
  if not admin.account_is_active_founder(p_actor) then
    raise exception using errcode='42501',message='research_founder_required';
  end if;

  select * into v_dataset from analytics.dataset_definitions
  where id=p_dataset_id and status in ('Draft','Active');
  if not found then raise exception using errcode='P0002',message='research_dataset_not_found'; end if;
  if v_dataset.dataset_kind <> 'HealthObservationAggregate' then
    raise exception using errcode='22023',message='research_dataset_adapter_mismatch';
  end if;
  -- System-generated rows need an explicit provenance chain to an eligible
  -- source before research eligibility can be proven.
  if v_dataset.source_category='SystemGenerated' then
    raise exception using errcode='42501',message='research_system_provenance_unverified';
  end if;

  select * into v_policy from analytics.dataset_privacy_policies where dataset_id=p_dataset_id;
  select * into v_export_policy from analytics.export_policies where purpose=v_dataset.purpose;
  if not found then raise exception using errcode='42501',message='research_export_policy_unknown'; end if;

  with eligible as (
    select distinct h.person_id
    from lifemate.health_observations h
    join core.persons p on p.id=h.person_id and p.status='Active'
    join core.account_person_links l
      on l.person_id=p.id and l.link_type='Self' and l.status='Active'
    where h.source_category=v_dataset.source_category
      and coalesce(h.provenance_restricted,false)=false
      and (not v_export_policy.requires_consent or consent.account_allows_optional_purpose(l.account_id,'research',p_jurisdiction))
      and (
        not (v_dataset.filter_json ? 'observationTypes') or
        h.observation_type in (select jsonb_array_elements_text(v_dataset.filter_json->'observationTypes'))
      )
      and (not (v_dataset.filter_json ? 'observedFrom') or h.observed_local_date >= (v_dataset.filter_json->>'observedFrom')::date)
      and (not (v_dataset.filter_json ? 'observedTo') or h.observed_local_date <= (v_dataset.filter_json->>'observedTo')::date)
      and (not (v_dataset.filter_json ? 'ageMin') or extract(year from age(h.observed_local_date,p.birth_date))::integer >= (v_dataset.filter_json->>'ageMin')::integer)
      and (not (v_dataset.filter_json ? 'ageMax') or extract(year from age(h.observed_local_date,p.birth_date))::integer <= (v_dataset.filter_json->>'ageMax')::integer)
      and (
        not (v_dataset.filter_json ? 'homeRegions') or
        p.home_region in (select jsonb_array_elements_text(v_dataset.filter_json->'homeRegions'))
      )
  ) select count(*)::integer into v_cohort from eligible;

  if v_cohort < greatest(v_policy.minimum_cohort_size,v_export_policy.minimum_cohort_size) then
    return jsonb_build_object(
      'datasetId',p_dataset_id,
      'datasetVersion',v_dataset.version,
      'privacyPolicyVersion',v_policy.policy_version,
      'eligible',false,
      'reason','minimum_cohort_not_met',
      'cohortSize',null,
      'cells','[]'::jsonb
    );
  end if;

  with source_rows as (
    select
      h.person_id,
      h.observation_type,
      h.unit_primary,
      h.value_primary,
      case when v_policy.age_bucket_years is null or p.birth_date is null then null
        else (
          greatest(0,(ceil(extract(year from age(h.observed_local_date,p.birth_date))::numeric / v_policy.age_bucket_years) * v_policy.age_bucket_years - v_policy.age_bucket_years)::integer)::text
          || '–' ||
          (ceil(extract(year from age(h.observed_local_date,p.birth_date))::numeric / v_policy.age_bucket_years) * v_policy.age_bucket_years)::integer::text
        ) end as age_bucket,
      p.home_region
    from lifemate.health_observations h
    join core.persons p on p.id=h.person_id and p.status='Active'
    join core.account_person_links l
      on l.person_id=p.id and l.link_type='Self' and l.status='Active'
    where h.source_category=v_dataset.source_category
      and coalesce(h.provenance_restricted,false)=false
      and (not v_export_policy.requires_consent or consent.account_allows_optional_purpose(l.account_id,'research',p_jurisdiction))
      and (not (v_dataset.filter_json ? 'observationTypes') or h.observation_type in (select jsonb_array_elements_text(v_dataset.filter_json->'observationTypes')))
      and (not (v_dataset.filter_json ? 'observedFrom') or h.observed_local_date >= (v_dataset.filter_json->>'observedFrom')::date)
      and (not (v_dataset.filter_json ? 'observedTo') or h.observed_local_date <= (v_dataset.filter_json->>'observedTo')::date)
      and (not (v_dataset.filter_json ? 'ageMin') or extract(year from age(h.observed_local_date,p.birth_date))::integer >= (v_dataset.filter_json->>'ageMin')::integer)
      and (not (v_dataset.filter_json ? 'ageMax') or extract(year from age(h.observed_local_date,p.birth_date))::integer <= (v_dataset.filter_json->>'ageMax')::integer)
      and (not (v_dataset.filter_json ? 'homeRegions') or p.home_region in (select jsonb_array_elements_text(v_dataset.filter_json->'homeRegions')))
  ), grouped as (
    select observation_type,unit_primary,age_bucket,home_region,
           count(distinct person_id)::integer as subject_count,
           count(*)::integer as observation_count,
           avg(value_primary) as average_value
    from source_rows
    group by observation_type,unit_primary,age_bucket,home_region
  )
  select coalesce(jsonb_agg(
    case when subject_count < v_policy.small_cell_threshold then
      jsonb_build_object(
        'observationType',observation_type,
        'unit',unit_primary,
        'ageBucket',age_bucket,
        'homeRegion',home_region,
        'suppressed',true,
        'subjectCount',null,
        'observationCount',null,
        'averageValue',null
      )
    else
      jsonb_build_object(
        'observationType',observation_type,
        'unit',unit_primary,
        'ageBucket',age_bucket,
        'homeRegion',home_region,
        'suppressed',false,
        'subjectCount',subject_count,
        'observationCount',observation_count,
        'averageValue',average_value
      )
    end
    order by observation_type,unit_primary,age_bucket,home_region
  ),'[]'::jsonb) into v_cells from grouped;

  return jsonb_build_object(
    'datasetId',p_dataset_id,
    'datasetVersion',v_dataset.version,
    'privacyPolicyVersion',v_policy.policy_version,
    'eligible',true,
    'reason',null,
    'cohortSize',v_cohort,
    'cells',v_cells
  );
end $$;

revoke all on function analytics.preview_research_health_observations(uuid,uuid,varchar) from public;
do $$ begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function analytics.preview_research_health_observations(uuid,uuid,varchar) to lifemate_admin_runtime;
  end if;
end $$;
