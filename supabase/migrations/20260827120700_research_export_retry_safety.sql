-- #497: persist only the privacy-checked aggregate preview used by a job so a
-- retry after an uncertain upload cannot regenerate different bytes.

alter table analytics.dataset_export_jobs
  add column if not exists preview_snapshot_json jsonb,
  add column if not exists claimed_at_utc timestamptz;

alter table analytics.dataset_export_jobs
  drop constraint if exists ck_dataset_export_preview_snapshot;
alter table analytics.dataset_export_jobs
  add constraint ck_dataset_export_preview_snapshot check (
    preview_snapshot_json is null or
    (jsonb_typeof(preview_snapshot_json)='object' and octet_length(preview_snapshot_json::text)<=1000000)
  );

create or replace function analytics.claim_research_export_for_worker(
  p_job_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns table(
  job_id uuid,
  dataset_id uuid,
  dataset_version integer,
  privacy_policy_version integer,
  export_format varchar,
  requested_by_account_id uuid,
  preview_json jsonb
)
language plpgsql
security definer
set search_path=analytics,admin,pg_temp
as $$
declare
  v_job analytics.dataset_export_jobs%rowtype;
  v_dataset analytics.dataset_definitions%rowtype;
  v_privacy analytics.dataset_privacy_policies%rowtype;
  v_policy analytics.export_policies%rowtype;
  v_preview jsonb;
begin
  select * into v_job from analytics.dataset_export_jobs where id=p_job_id for update;
  if not found then return; end if;

  if v_job.status='Processing' and v_job.preview_snapshot_json is not null then
    return query select v_job.id,v_job.dataset_id,v_job.dataset_version,v_job.privacy_policy_version,v_job.format,v_job.requested_by_account_id,v_job.preview_snapshot_json;
    return;
  end if;
  if v_job.status <> 'Pending' then return; end if;

  select * into v_dataset from analytics.dataset_definitions where id=v_job.dataset_id;
  select * into v_privacy from analytics.dataset_privacy_policies where dataset_id=v_job.dataset_id;
  select * into v_policy from analytics.export_policies where purpose=v_job.purpose;
  if v_dataset.status <> 'Active' or v_dataset.version <> v_job.dataset_version or
     v_privacy.policy_version <> v_job.privacy_policy_version or v_policy.enabled is distinct from true then
    update analytics.dataset_export_jobs set status='Rejected',reason_code='policy_or_version_changed',updated_at_utc=now() where id=p_job_id;
    update analytics.export_audit set outcome='Rejected',reason_code='policy_or_version_changed' where export_job_id=p_job_id;
    return;
  end if;

  v_preview := analytics.preview_research_dataset(v_job.requested_by_account_id,v_job.dataset_id,p_jurisdiction);
  if coalesce((v_preview->>'eligible')::boolean,false) is distinct from true then
    update analytics.dataset_export_jobs set status='Rejected',reason_code='privacy_gate_changed',cohort_size=null,updated_at_utc=now() where id=p_job_id;
    update analytics.export_audit set outcome='Rejected',reason_code='privacy_gate_changed',cohort_size=null where export_job_id=p_job_id;
    return;
  end if;
  if octet_length(v_preview::text)>1000000 then
    update analytics.dataset_export_jobs set status='Rejected',reason_code='preview_too_large',updated_at_utc=now() where id=p_job_id;
    update analytics.export_audit set outcome='Rejected',reason_code='preview_too_large' where export_job_id=p_job_id;
    return;
  end if;

  update analytics.dataset_export_jobs
  set status='Processing',cohort_size=(v_preview->>'cohortSize')::integer,
      preview_snapshot_json=v_preview,claimed_at_utc=now(),updated_at_utc=now()
  where id=p_job_id;
  return query select v_job.id,v_job.dataset_id,v_job.dataset_version,v_job.privacy_policy_version,v_job.format,v_job.requested_by_account_id,v_preview;
end $$;

create or replace function analytics.list_research_export_jobs(p_actor uuid,p_dataset_id uuid default null)
returns table(
  job_id uuid,dataset_id uuid,dataset_version integer,privacy_policy_version integer,
  export_format varchar,status varchar,cohort_size integer,reason_code varchar,
  artifact_sha256 char(64),artifact_expires_at_utc timestamptz,created_at_utc timestamptz,updated_at_utc timestamptz
)
language plpgsql stable security definer set search_path=analytics,admin,pg_temp as $$
begin
  if not admin.account_is_active_founder(p_actor) then raise exception using errcode='42501',message='research_founder_required'; end if;
  return query
  select j.id,j.dataset_id,j.dataset_version,j.privacy_policy_version,j.format,j.status,j.cohort_size,j.reason_code,
         j.artifact_sha256,j.artifact_expires_at_utc,j.created_at_utc,j.updated_at_utc
  from analytics.dataset_export_jobs j
  where j.requested_by_account_id=p_actor and (p_dataset_id is null or j.dataset_id=p_dataset_id)
  order by j.created_at_utc desc,j.id desc
  limit 500;
end $$;

create or replace function analytics.get_research_export_download(
  p_actor uuid,p_job_id uuid
) returns table(storage_object_path varchar,artifact_sha256 char(64),export_format varchar,artifact_expires_at_utc timestamptz)
language plpgsql stable security definer set search_path=analytics,admin,pg_temp as $$
begin
  if not admin.account_is_active_founder(p_actor) then raise exception using errcode='42501',message='research_founder_required'; end if;
  return query
  select j.artifact_storage_path,j.artifact_sha256,j.format,j.artifact_expires_at_utc
  from analytics.dataset_export_jobs j
  where j.id=p_job_id and j.requested_by_account_id=p_actor and j.status='Completed' and j.artifact_expires_at_utc>now();
end $$;

revoke all on function analytics.list_research_export_jobs(uuid,uuid) from public;
revoke all on function analytics.get_research_export_download(uuid,uuid) from public;
do $$ begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function analytics.list_research_export_jobs(uuid,uuid) to lifemate_admin_runtime;
    grant execute on function analytics.get_research_export_download(uuid,uuid) to lifemate_admin_runtime;
  end if;
end $$;
