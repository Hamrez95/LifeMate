-- #497 exact-review hardening.
-- Dataset definitions may be drafted against a known policy even while export
-- execution remains disabled. Export execution will enforce enabled+consent.

insert into analytics.export_policies(
  purpose,enabled,minimum_cohort_size,requires_consent,
  requires_legal_review,requires_policy_review,requires_jurisdiction_review
) values (
  'research_deidentified_dataset',false,20,true,false,true,false
)
on conflict (purpose) do nothing;

alter table analytics.dataset_export_jobs
  drop constraint if exists fk_dataset_export_jobs_purpose;
alter table analytics.dataset_export_jobs
  add constraint fk_dataset_export_jobs_purpose
  foreign key (purpose) references analytics.export_policies(purpose) on delete restrict;

alter table analytics.dataset_export_jobs
  drop constraint if exists ck_dataset_export_jobs_versions;
alter table analytics.dataset_export_jobs
  add constraint ck_dataset_export_jobs_versions
  check (dataset_version >= 1 and privacy_policy_version >= 1);

alter table analytics.dataset_export_jobs
  drop constraint if exists ck_dataset_export_jobs_cohort;
alter table analytics.dataset_export_jobs
  add constraint ck_dataset_export_jobs_cohort
  check (cohort_size is null or cohort_size >= 0);

alter table analytics.dataset_export_jobs
  drop constraint if exists ck_dataset_export_jobs_expiry;
alter table analytics.dataset_export_jobs
  add constraint ck_dataset_export_jobs_expiry
  check (artifact_expires_at_utc is null or artifact_expires_at_utc > created_at_utc);

create or replace function analytics.create_research_dataset(
  p_actor uuid,p_name varchar,p_purpose varchar,p_source_category varchar,p_filter jsonb,
  p_age_bucket_years smallint,p_minimum_cohort_size integer,p_small_cell_threshold integer,
  p_quasi_identifier_rules jsonb,p_row_mode varchar,p_correlation_id uuid
) returns uuid
language plpgsql security definer set search_path=analytics,admin,pg_temp as $$
declare v_id uuid; v_policy_min integer; v_research_allowed boolean;
begin
  if p_correlation_id is null then raise exception using errcode='22023',message='research_correlation_required'; end if;
  if not admin.account_is_active_founder(p_actor) then raise exception using errcode='42501',message='research_founder_required'; end if;
  select minimum_cohort_size into v_policy_min from analytics.export_policies where purpose=p_purpose;
  if v_policy_min is null then raise exception using errcode='42501',message='research_export_policy_unknown'; end if;
  select research_allowed into v_research_allowed from analytics.source_policies where source_category=p_source_category;
  if v_research_allowed is distinct from true then raise exception using errcode='42501',message='research_source_not_allowed'; end if;
  if p_minimum_cohort_size < greatest(v_policy_min,5) or p_small_cell_threshold < 5 or p_small_cell_threshold > p_minimum_cohort_size then
    raise exception using errcode='22023',message='research_privacy_threshold_invalid';
  end if;
  if p_row_mode not in ('Aggregate','Pseudonymous') then raise exception using errcode='22023',message='research_row_mode_invalid'; end if;
  if jsonb_typeof(coalesce(p_filter,'{}'::jsonb)) <> 'object' or octet_length(coalesce(p_filter,'{}'::jsonb)::text)>16000 then raise exception using errcode='22023',message='research_filter_invalid'; end if;
  if jsonb_typeof(coalesce(p_quasi_identifier_rules,'{}'::jsonb)) <> 'object' or octet_length(coalesce(p_quasi_identifier_rules,'{}'::jsonb)::text)>16000 then raise exception using errcode='22023',message='research_transform_invalid'; end if;
  insert into analytics.dataset_definitions(name,purpose,source_category,filter_json,created_by_account_id)
  values(trim(p_name),p_purpose,p_source_category,coalesce(p_filter,'{}'::jsonb),p_actor) returning id into v_id;
  insert into analytics.dataset_privacy_policies(dataset_id,age_bucket_years,minimum_cohort_size,small_cell_threshold,quasi_identifier_rules,row_mode,updated_by_account_id)
  values(v_id,p_age_bucket_years,p_minimum_cohort_size,p_small_cell_threshold,coalesce(p_quasi_identifier_rules,'{}'::jsonb),p_row_mode,p_actor);
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,metadata_json)
  values(p_actor,'research.dataset.created','research_dataset',v_id::text,'Succeeded',p_correlation_id,jsonb_build_object('purpose',p_purpose,'sourceCategory',p_source_category,'rowMode',p_row_mode,'minimumCohortSize',p_minimum_cohort_size,'smallCellThreshold',p_small_cell_threshold));
  return v_id;
end $$;

revoke all on function analytics.create_research_dataset(uuid,varchar,varchar,varchar,jsonb,smallint,integer,integer,jsonb,varchar,uuid) from public;
do $$ begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function analytics.create_research_dataset(uuid,varchar,varchar,varchar,jsonb,smallint,integer,integer,jsonb,varchar,uuid) to lifemate_admin_runtime;
  end if;
end $$;
