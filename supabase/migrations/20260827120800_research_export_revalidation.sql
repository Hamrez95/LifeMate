-- #497: every retry re-evaluates current consent/policy/cohort. A previously
-- captured aggregate snapshot is reusable only when the freshly computed
-- privacy-safe preview is byte-for-byte equivalent.

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
  if not found or v_job.status not in ('Pending','Processing') then return; end if;

  select * into v_dataset from analytics.dataset_definitions where id=v_job.dataset_id;
  select * into v_privacy from analytics.dataset_privacy_policies where dataset_id=v_job.dataset_id;
  select * into v_policy from analytics.export_policies where purpose=v_job.purpose;
  if v_dataset.status <> 'Active' or v_dataset.version <> v_job.dataset_version or
     v_privacy.policy_version <> v_job.privacy_policy_version or v_policy.enabled is distinct from true then
    update analytics.dataset_export_jobs
      set status='Rejected',reason_code='policy_or_version_changed',preview_snapshot_json=null,updated_at_utc=now()
      where id=p_job_id;
    update analytics.export_audit set outcome='Rejected',reason_code='policy_or_version_changed' where export_job_id=p_job_id;
    return;
  end if;

  v_preview := analytics.preview_research_dataset(v_job.requested_by_account_id,v_job.dataset_id,p_jurisdiction);
  if coalesce((v_preview->>'eligible')::boolean,false) is distinct from true then
    update analytics.dataset_export_jobs
      set status='Rejected',reason_code='privacy_gate_changed',cohort_size=null,preview_snapshot_json=null,updated_at_utc=now()
      where id=p_job_id;
    update analytics.export_audit set outcome='Rejected',reason_code='privacy_gate_changed',cohort_size=null where export_job_id=p_job_id;
    return;
  end if;
  if octet_length(v_preview::text)>1000000 then
    update analytics.dataset_export_jobs
      set status='Rejected',reason_code='preview_too_large',preview_snapshot_json=null,updated_at_utc=now()
      where id=p_job_id;
    update analytics.export_audit set outcome='Rejected',reason_code='preview_too_large' where export_job_id=p_job_id;
    return;
  end if;

  if v_job.status='Processing' and v_job.preview_snapshot_json is not null and v_job.preview_snapshot_json <> v_preview then
    update analytics.dataset_export_jobs
      set status='Rejected',reason_code='aggregate_snapshot_changed',preview_snapshot_json=null,updated_at_utc=now()
      where id=p_job_id;
    update analytics.export_audit set outcome='Rejected',reason_code='aggregate_snapshot_changed' where export_job_id=p_job_id;
    return;
  end if;

  update analytics.dataset_export_jobs
  set status='Processing',cohort_size=(v_preview->>'cohortSize')::integer,
      preview_snapshot_json=coalesce(preview_snapshot_json,v_preview),
      claimed_at_utc=coalesce(claimed_at_utc,now()),updated_at_utc=now()
  where id=p_job_id;

  return query select v_job.id,v_job.dataset_id,v_job.dataset_version,v_job.privacy_policy_version,
    v_job.format,v_job.requested_by_account_id,coalesce(v_job.preview_snapshot_json,v_preview);
end $$;
