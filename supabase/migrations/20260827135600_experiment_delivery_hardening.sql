begin;

alter table analytics.experiments
  add column if not exists segment_snapshot_id uuid references audience.segment_snapshots(id) on delete restrict;

alter table analytics.experiments
  drop constraint if exists ck_experiments_segment_snapshot_pair;
alter table analytics.experiments
  add constraint ck_experiments_segment_snapshot_pair
  check ((segment_key is null) = (segment_snapshot_id is null));

alter table analytics.experiment_exposures
  add column if not exists subject_hash varchar(64);
update analytics.experiment_exposures set subject_hash=idempotency_hash where subject_hash is null;
alter table analytics.experiment_exposures alter column subject_hash set not null;
alter table analytics.experiment_exposures
  drop constraint if exists ck_experiment_exposures_subject_hash;
alter table analytics.experiment_exposures
  add constraint ck_experiment_exposures_subject_hash check (subject_hash ~ '^[0-9a-f]{64}$');
create unique index if not exists uq_experiment_exposure_subject
  on analytics.experiment_exposures(experiment_key,subject_hash);

-- Replace the v1 create contract with a segment-snapshot-bound contract. Dynamic
-- segment definitions are not consulted at delivery time; an immutable snapshot
-- prevents audience drift between review and exposure.
drop function if exists admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar);
create or replace function admin.create_experiment(
  p_actor_account_id uuid,
  p_experiment_key varchar,
  p_name varchar,
  p_control_key varchar,
  p_surface_code varchar,
  p_product_code varchar,
  p_segment_key varchar,
  p_segment_snapshot_id uuid,
  p_primary_metric_code varchar,
  p_guardrail_metric_codes varchar[],
  p_variants jsonb,
  p_starts_at_utc timestamptz,
  p_ends_at_utc timestamptz,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,analytics,platform,audience,admin,pg_temp
as $$
declare
  v_existing admin.idempotency_keys%rowtype;
  v_response jsonb;
  v_variant jsonb;
  v_control platform.controls%rowtype;
  v_segment audience.segments%rowtype;
  v_snapshot audience.segment_snapshots%rowtype;
  v_weight_total integer:=0;
  v_variant_count integer:=0;
  v_guardrail_count integer:=0;
  v_operation varchar(160):='experiments.create';
begin
  if not admin.account_has_permission(p_actor_account_id,'experiments.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_experiment_key is null or p_experiment_key !~ '^[a-z][a-z0-9._-]{2,95}$'
     or p_name is null or length(trim(p_name)) not between 3 and 160
     or p_control_key is null or p_control_key !~ '^[a-z][a-z0-9._-]{2,95}$'
     or p_surface_code not in ('onboarding','pricing','paywall','cta','offer','nonclinical_feature')
     or (p_product_code is not null and p_product_code !~ '^[a-z0-9][a-z0-9._:-]{0,63}$')
     or (p_segment_key is null)<>(p_segment_snapshot_id is null) then
    return jsonb_build_object('httpStatus',400,'code','experiment_payload_invalid','message','Experiment definition is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then
    return jsonb_build_object('httpStatus',400,'code','experiment_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;
  if p_ends_at_utc is not null and p_starts_at_utc is not null and p_ends_at_utc<=p_starts_at_utc then
    return jsonb_build_object('httpStatus',400,'code','experiment_window_invalid','message','Experiment end must be after start.','replayed',false);
  end if;

  select * into v_control from platform.controls where control_key=p_control_key and status='Active';
  if not found then
    return jsonb_build_object('httpStatus',409,'code','experiment_control_unavailable','message','Experiment control must reference an active platform control.','replayed',false);
  end if;

  if p_segment_key is not null then
    select * into v_segment from audience.segments where segment_key=p_segment_key and status='Active';
    if not found then
      return jsonb_build_object('httpStatus',409,'code','experiment_segment_unavailable','message','Experiment segment must be active.','replayed',false);
    end if;
    select * into v_snapshot from audience.segment_snapshots where id=p_segment_snapshot_id;
    if not found or v_snapshot.segment_id<>v_segment.id or v_snapshot.segment_version<>v_segment.version then
      return jsonb_build_object('httpStatus',409,'code','experiment_segment_snapshot_stale','message','Experiment must bind the current reviewed segment snapshot.','replayed',false);
    end if;
  end if;

  if not exists(select 1 from analytics.experiment_metric_registry where metric_code=p_primary_metric_code) then
    return jsonb_build_object('httpStatus',400,'code','experiment_metric_unknown','message','Primary metric is not canonical.','replayed',false);
  end if;
  if cardinality(coalesce(p_guardrail_metric_codes,'{}'))>8
     or p_primary_metric_code=any(coalesce(p_guardrail_metric_codes,'{}'))
     or exists(select 1 from unnest(coalesce(p_guardrail_metric_codes,'{}')) g where g !~ '^[a-z][a-z0-9._-]{2,95}$')
     or exists(select 1 from unnest(coalesce(p_guardrail_metric_codes,'{}')) g where not exists(select 1 from analytics.experiment_metric_registry r where r.metric_code=g)) then
    return jsonb_build_object('httpStatus',400,'code','experiment_guardrails_invalid','message','Experiment guardrails are invalid.','replayed',false);
  end if;
  select count(*) into v_guardrail_count from (select distinct g from unnest(coalesce(p_guardrail_metric_codes,'{}')) g) q;
  if v_guardrail_count<>cardinality(coalesce(p_guardrail_metric_codes,'{}')) then
    return jsonb_build_object('httpStatus',400,'code','experiment_guardrails_invalid','message','Experiment guardrails must be unique.','replayed',false);
  end if;
  if jsonb_typeof(p_variants)<>'array' or jsonb_array_length(p_variants) not between 2 and 10 then
    return jsonb_build_object('httpStatus',400,'code','experiment_variants_invalid','message','Experiment variants are invalid.','replayed',false);
  end if;
  for v_variant in select value from jsonb_array_elements(p_variants) loop
    if coalesce(v_variant->>'key','') !~ '^[a-z][a-z0-9._-]{2,95}$'
       or coalesce(v_variant->>'weightBasisPoints','') !~ '^[0-9]{1,5}$'
       or (v_variant->>'weightBasisPoints')::integer not between 1 and 10000
       or not (v_variant ? 'controlValue')
       or octet_length((v_variant->'controlValue')::text)>4096
       or (v_control.value_type='Boolean' and jsonb_typeof(v_variant->'controlValue')<>'boolean')
       or (v_control.value_type='Integer' and (jsonb_typeof(v_variant->'controlValue')<>'number' or ((v_variant->>'controlValue')::numeric % 1)<>0))
       or (v_control.value_type='String' and jsonb_typeof(v_variant->'controlValue')<>'string') then
      return jsonb_build_object('httpStatus',400,'code','experiment_variant_invalid','message','Experiment variant is invalid or incompatible with the platform control type.','replayed',false);
    end if;
    v_weight_total:=v_weight_total+(v_variant->>'weightBasisPoints')::integer;
    v_variant_count:=v_variant_count+1;
  end loop;
  if v_weight_total<>10000 or v_variant_count<>(select count(distinct value->>'key') from jsonb_array_elements(p_variants)) then
    return jsonb_build_object('httpStatus',400,'code','experiment_variant_weights_invalid','message','Variant weights must total 10000 and keys must be unique.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json || jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  if exists(select 1 from analytics.experiments where experiment_key=p_experiment_key) then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_exists','message','Experiment key already exists.','replayed',false);
  else
    insert into analytics.experiments(
      experiment_key,name,control_key,surface_code,product_code,segment_key,segment_snapshot_id,
      primary_metric_code,guardrail_metric_codes,status,starts_at_utc,ends_at_utc,created_by_account_id,updated_by_account_id
    ) values(
      p_experiment_key,trim(p_name),p_control_key,p_surface_code,nullif(trim(p_product_code),''),p_segment_key,p_segment_snapshot_id,
      p_primary_metric_code,coalesce(p_guardrail_metric_codes,'{}'),'Draft',p_starts_at_utc,p_ends_at_utc,p_actor_account_id,p_actor_account_id
    );
    for v_variant in select value from jsonb_array_elements(p_variants) loop
      insert into analytics.experiment_variants(experiment_key,variant_key,weight_basis_points,control_value)
      values(p_experiment_key,v_variant->>'key',(v_variant->>'weightBasisPoints')::integer,v_variant->'controlValue');
    end loop;
    v_response:=jsonb_build_object('httpStatus',201,'code','created','experimentKey',p_experiment_key,'status','Draft','version',1,'replayed',false);
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'experiment',p_experiment_key,
    case when (v_response->>'httpStatus')::integer<400 then 'Succeeded' else 'Denied' end,
    case when (v_response->>'httpStatus')::integer<400 then trim(p_reason) else coalesce(v_response->>'message','Experiment creation denied.') end,
    p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('surface',p_surface_code,'productCode',p_product_code,'segmentKey',p_segment_key,'segmentSnapshotId',p_segment_snapshot_id,'primaryMetricCode',p_primary_metric_code,'variantCount',v_variant_count,'code',v_response->>'code'));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

-- No direct experiment-table SELECT is granted to the consumer Edge runtime.
-- This narrow function returns only currently eligible, reviewed definitions and
-- checks immutable segment snapshot membership server-side.
create or replace function analytics.get_eligible_experiments(
  p_account_id uuid,
  p_product_code varchar
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,analytics,platform,audience,pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'key',e.experiment_key,
    'controlKey',e.control_key,
    'surface',e.surface_code,
    'productCode',e.product_code,
    'experimentVersion',e.version,
    'valueType',c.value_type,
    'variants',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'key',v.variant_key,
        'weightBasisPoints',v.weight_basis_points,
        'controlValue',v.control_value,
        'version',v.version
      ) order by v.variant_key),'[]'::jsonb)
      from analytics.experiment_variants v where v.experiment_key=e.experiment_key
    )
  ) order by e.experiment_key),'[]'::jsonb)
  from analytics.experiments e
  join platform.controls c on c.control_key=e.control_key and c.status='Active'
  where e.status='Running'
    and (e.starts_at_utc is null or e.starts_at_utc<=now())
    and (e.ends_at_utc is null or e.ends_at_utc>now())
    and (e.product_code is null or e.product_code=p_product_code)
    and (
      e.segment_snapshot_id is null or exists(
        select 1 from audience.segment_snapshot_members sm
        where sm.snapshot_id=e.segment_snapshot_id and sm.account_id=p_account_id
      )
    )
    and not exists(
      select 1 from platform.control_rules r
      where r.control_key=e.control_key and r.status='Active'
        and (r.starts_at_utc is null or r.starts_at_utc<=now())
        and (r.ends_at_utc is null or r.ends_at_utc>now())
    );
$$;

-- Replace exposure recorder with a pseudonymous-subject-aware idempotent contract.
drop function if exists analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,varchar,timestamptz,jsonb);
create or replace function analytics.record_experiment_exposure(
  p_experiment_key varchar,
  p_experiment_version bigint,
  p_variant_key varchar,
  p_variant_version bigint,
  p_subject_hash varchar,
  p_idempotency_hash varchar,
  p_occurred_at_utc timestamptz,
  p_metadata_json jsonb default '{}'::jsonb
) returns boolean
language plpgsql
security definer
set search_path=pg_catalog,analytics,pg_temp
as $$
declare
  v_experiment analytics.experiments%rowtype;
  v_metadata_text text;
  v_inserted integer:=0;
begin
  v_metadata_text:=lower(coalesce(p_metadata_json,'{}'::jsonb)::text);
  if p_subject_hash is null or p_subject_hash !~ '^[0-9a-f]{64}$'
     or p_idempotency_hash is null or p_idempotency_hash !~ '^[0-9a-f]{64}$'
     or p_occurred_at_utc is null
     or p_metadata_json is null or jsonb_typeof(p_metadata_json)<>'object'
     or octet_length(p_metadata_json::text)>2048
     or v_metadata_text ~ '"(phone|email|name|account[_-]?id|person[_-]?id|health|medication|diagnosis|treatment|cycle|note|symptom)"\s*:' then
    return false;
  end if;
  select * into v_experiment from analytics.experiments where experiment_key=p_experiment_key;
  if not found or v_experiment.status<>'Running' or v_experiment.version<>p_experiment_version
     or (v_experiment.starts_at_utc is not null and p_occurred_at_utc<v_experiment.starts_at_utc)
     or (v_experiment.ends_at_utc is not null and p_occurred_at_utc>=v_experiment.ends_at_utc)
     or not exists(select 1 from analytics.experiment_variants where experiment_key=p_experiment_key and variant_key=p_variant_key and version=p_variant_version) then
    return false;
  end if;
  insert into analytics.experiment_exposures(
    experiment_key,experiment_version,variant_key,variant_version,subject_hash,idempotency_hash,occurred_at_utc,metadata_json
  ) values(
    p_experiment_key,p_experiment_version,p_variant_key,p_variant_version,p_subject_hash,p_idempotency_hash,p_occurred_at_utc,p_metadata_json
  ) on conflict do nothing;
  get diagnostics v_inserted=row_count;
  return v_inserted=1 or exists(
    select 1 from analytics.experiment_exposures
    where experiment_key=p_experiment_key and subject_hash=p_subject_hash
      and variant_key=p_variant_key and variant_version=p_variant_version
  );
end $$;

revoke all on function admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,uuid,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar) from public;
revoke all on function analytics.get_eligible_experiments(uuid,varchar) from public;
revoke all on function analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,varchar,varchar,timestamptz,jsonb) from public;
do $$ begin
  if to_regrole('anon') is not null then
    execute 'revoke all on function admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,uuid,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar) from anon';
    execute 'revoke all on function analytics.get_eligible_experiments(uuid,varchar) from anon';
    execute 'revoke all on function analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,varchar,varchar,timestamptz,jsonb) from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on function admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,uuid,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar) from authenticated';
    execute 'revoke all on function analytics.get_eligible_experiments(uuid,varchar) from authenticated';
    execute 'revoke all on function analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,varchar,varchar,timestamptz,jsonb) from authenticated';
  end if;
end $$;
grant execute on function admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,uuid,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function analytics.get_eligible_experiments(uuid,varchar) to lifemate_edge_runtime;
grant execute on function analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,varchar,varchar,timestamptz,jsonb) to lifemate_edge_runtime;

comment on column analytics.experiments.segment_snapshot_id is 'Immutable audience snapshot bound at experiment creation; prevents dynamic segment drift during delivery.';
comment on column analytics.experiment_exposures.subject_hash is 'Server-HMAC pseudonymous subject key for unique sample accounting; raw Account/Person identifiers are not stored.';

commit;
