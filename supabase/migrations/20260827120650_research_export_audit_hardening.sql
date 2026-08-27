-- #497 exact-review: audit completion must target exactly one export job and
-- Supabase pgcrypto functions live in the extensions schema.

alter table analytics.export_audit
  add column if not exists export_job_id uuid references analytics.dataset_export_jobs(id) on delete restrict;
create unique index if not exists ux_analytics_export_audit_job
  on analytics.export_audit(export_job_id) where export_job_id is not null;

create or replace function analytics.request_research_export(
  p_actor uuid,
  p_dataset_id uuid,
  p_format varchar,
  p_correlation_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns uuid
language plpgsql
security definer
set search_path=analytics,admin,integration,extensions,pg_temp
as $$
declare
  v_dataset analytics.dataset_definitions%rowtype;
  v_privacy analytics.dataset_privacy_policies%rowtype;
  v_export_policy analytics.export_policies%rowtype;
  v_preview jsonb;
  v_job_id uuid;
  v_filter_hash char(64);
begin
  if not admin.account_is_active_founder(p_actor) then raise exception using errcode='42501',message='research_founder_required'; end if;
  if p_correlation_id is null then raise exception using errcode='22023',message='research_correlation_required'; end if;
  if p_format not in ('CSV','XLSX') then raise exception using errcode='22023',message='research_export_format_invalid'; end if;

  select * into v_dataset from analytics.dataset_definitions where id=p_dataset_id and status='Active' for share;
  if not found then raise exception using errcode='42501',message='research_dataset_not_active'; end if;
  select * into v_privacy from analytics.dataset_privacy_policies where dataset_id=p_dataset_id;
  select * into v_export_policy from analytics.export_policies where purpose=v_dataset.purpose;
  if not found or v_export_policy.enabled is distinct from true then
    raise exception using errcode='42501',message='research_export_policy_disabled';
  end if;
  if v_privacy.row_mode <> 'Aggregate' then
    raise exception using errcode='0A000',message='research_pseudonymous_export_not_ready';
  end if;

  v_preview := analytics.preview_research_dataset(p_actor,p_dataset_id,p_jurisdiction);
  if coalesce((v_preview->>'eligible')::boolean,false) is distinct from true then
    raise exception using errcode='42501',message='research_privacy_gate_failed';
  end if;
  v_filter_hash := encode(extensions.digest(convert_to(v_dataset.filter_json::text,'UTF8'),'sha256'),'hex');

  insert into analytics.dataset_export_jobs(
    dataset_id,dataset_version,privacy_policy_version,requested_by_account_id,purpose,format,status,cohort_size
  ) values (
    p_dataset_id,v_dataset.version,v_privacy.policy_version,p_actor,v_dataset.purpose,p_format,'Pending',(v_preview->>'cohortSize')::integer
  ) returning id into v_job_id;

  insert into analytics.export_audit(
    purpose,requested_by_account_id,metric_key,outcome,reason_code,cohort_size,
    dataset_id,dataset_version,privacy_policy_version,filter_sha256,export_format,export_job_id
  ) values (
    v_dataset.purpose,p_actor,'research.dataset.export','Requested','pending',(v_preview->>'cohortSize')::integer,
    p_dataset_id,v_dataset.version,v_privacy.policy_version,v_filter_hash,p_format,v_job_id
  );

  insert into integration.outbox_messages(
    aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,priority,max_attempts,max_age_seconds
  ) values (
    'ResearchDatasetExport',v_job_id,'analytics.research_export_requested',
    'research-export:'||v_job_id::text,jsonb_build_object('jobId',v_job_id),40,5,86400
  );

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,metadata_json)
  values(p_actor,'research.export.requested','research_export_job',v_job_id::text,'Succeeded',p_correlation_id,
    jsonb_build_object('datasetId',p_dataset_id,'datasetVersion',v_dataset.version,'privacyPolicyVersion',v_privacy.policy_version,'format',p_format,'cohortSize',(v_preview->>'cohortSize')::integer));
  return v_job_id;
end $$;

create or replace function analytics.complete_research_export_for_worker(
  p_job_id uuid,
  p_artifact_storage_path varchar,
  p_artifact_sha256 char(64),
  p_artifact_expires_at timestamptz
) returns boolean
language plpgsql
security definer
set search_path=analytics,pg_temp
as $$
declare v_job analytics.dataset_export_jobs%rowtype;
begin
  if p_artifact_storage_path is null or p_artifact_storage_path ~ '(\.\.|^/|://)' or length(p_artifact_storage_path)>500 then
    raise exception using errcode='22023',message='research_artifact_path_invalid';
  end if;
  if p_artifact_sha256 is null or p_artifact_sha256 !~ '^[0-9a-f]{64}$' then raise exception using errcode='22023',message='research_artifact_hash_invalid'; end if;
  if p_artifact_expires_at is null or p_artifact_expires_at <= now() or p_artifact_expires_at > now()+interval '7 days' then
    raise exception using errcode='22023',message='research_artifact_expiry_invalid';
  end if;
  select * into v_job from analytics.dataset_export_jobs where id=p_job_id for update;
  if not found then return false; end if;
  if v_job.status='Completed' then
    return v_job.artifact_storage_path=p_artifact_storage_path and v_job.artifact_sha256=p_artifact_sha256 and v_job.artifact_expires_at_utc=p_artifact_expires_at;
  end if;
  if v_job.status <> 'Processing' then return false; end if;
  update analytics.dataset_export_jobs set status='Completed',artifact_storage_path=p_artifact_storage_path,artifact_sha256=p_artifact_sha256,artifact_expires_at_utc=p_artifact_expires_at,reason_code=null,updated_at_utc=now() where id=p_job_id;
  update analytics.export_audit set outcome='Completed',reason_code='completed',artifact_sha256=p_artifact_sha256,artifact_expires_at_utc=p_artifact_expires_at where export_job_id=p_job_id;
  return true;
end $$;

create or replace function analytics.fail_research_export_for_worker(p_job_id uuid,p_reason_code varchar) returns boolean
language plpgsql
security definer
set search_path=analytics,pg_temp
as $$
declare v_job analytics.dataset_export_jobs%rowtype;
begin
  if p_reason_code is null or p_reason_code !~ '^[a-z][a-z0-9._-]{2,99}$' then raise exception using errcode='22023',message='research_export_reason_invalid'; end if;
  select * into v_job from analytics.dataset_export_jobs where id=p_job_id for update;
  if not found then return false; end if;
  if v_job.status in ('Completed','Rejected','Expired') then return false; end if;
  update analytics.dataset_export_jobs set status='Failed',reason_code=p_reason_code,updated_at_utc=now() where id=p_job_id;
  update analytics.export_audit set outcome='Failed',reason_code=p_reason_code where export_job_id=p_job_id;
  return true;
end $$;
