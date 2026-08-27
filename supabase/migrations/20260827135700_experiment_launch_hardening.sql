begin;

alter table analytics.experiments add column if not exists control_definition_version bigint;
update analytics.experiments e
set control_definition_version=c.version
from platform.controls c
where c.control_key=e.control_key and e.control_definition_version is null;
alter table analytics.experiments alter column control_definition_version set not null;
alter table analytics.experiments
  drop constraint if exists ck_experiments_control_definition_version;
alter table analytics.experiments
  add constraint ck_experiments_control_definition_version check (control_definition_version>=1);

create or replace function analytics.pin_experiment_control_version()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,analytics,platform,pg_temp
as $$
declare
  v_version bigint;
begin
  select version into v_version from platform.controls
  where control_key=new.control_key and status='Active';
  if v_version is null then
    raise exception 'experiment_control_unavailable' using errcode='23514';
  end if;
  if tg_op='INSERT' then
    new.control_definition_version:=v_version;
  elsif new.control_key<>old.control_key then
    raise exception 'experiment_control_immutable' using errcode='23514';
  end if;
  return new;
end $$;

drop trigger if exists trg_experiment_pin_control_version on analytics.experiments;
create trigger trg_experiment_pin_control_version
before insert or update of control_key on analytics.experiments
for each row execute function analytics.pin_experiment_control_version();

create or replace function admin.set_experiment_status(
  p_actor_account_id uuid,
  p_experiment_key varchar,
  p_status varchar,
  p_expected_version bigint,
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
  v_experiment analytics.experiments%rowtype;
  v_response jsonb;
  v_total integer;
  v_operation varchar(160):='experiments.status';
begin
  if not admin.account_has_permission(p_actor_account_id,'experiments.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_status not in ('Scheduled','Running','Paused','Stopped','Completed') then
    return jsonb_build_object('httpStatus',400,'code','experiment_status_invalid','message','Experiment status is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then
    return jsonb_build_object('httpStatus',400,'code','experiment_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
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

  select * into v_experiment from analytics.experiments where experiment_key=p_experiment_key for update;
  if not found then
    v_response:=jsonb_build_object('httpStatus',404,'code','experiment_not_found','message','Experiment was not found.','replayed',false);
  elsif p_expected_version is null or p_expected_version<>v_experiment.version then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_version_conflict','message','Experiment changed; refresh before updating.','currentVersion',v_experiment.version,'replayed',false);
  elsif v_experiment.status in ('Stopped','Completed') then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_terminal','message','Terminal experiments cannot be restarted.','replayed',false);
  elsif not (
    (v_experiment.status='Draft' and p_status in ('Scheduled','Stopped')) or
    (v_experiment.status='Scheduled' and p_status in ('Running','Stopped')) or
    (v_experiment.status='Running' and p_status in ('Paused','Stopped','Completed')) or
    (v_experiment.status='Paused' and p_status in ('Running','Stopped','Completed'))
  ) then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_transition_invalid','message','Experiment status transition is not allowed.','replayed',false);
  elsif p_status in ('Scheduled','Running') and not exists(
    select 1 from platform.controls c where c.control_key=v_experiment.control_key
      and c.status='Active' and c.version=v_experiment.control_definition_version
  ) then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_control_version_drift','message','Platform control changed after experiment review. Recreate or re-review the experiment.','replayed',false);
  elsif p_status in ('Scheduled','Running') and exists(
    select 1 from platform.control_rules r where r.control_key=v_experiment.control_key
      and r.status='Active' and (r.starts_at_utc is null or r.starts_at_utc<=now())
      and (r.ends_at_utc is null or r.ends_at_utc>now())
  ) then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_control_rule_conflict','message','Active Remote Config rules conflict with experiment ownership of this control.','replayed',false);
  elsif p_status in ('Scheduled','Running') and exists(
    select 1 from analytics.experiment_metric_registry r
    where (r.metric_code=v_experiment.primary_metric_code or r.metric_code=any(v_experiment.guardrail_metric_codes))
      and r.measurement_state='Unavailable'
  ) then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_metric_unavailable','message','Every experiment metric must have canonical measurement support before launch.','replayed',false);
  elsif p_status in ('Scheduled','Running') and v_experiment.segment_snapshot_id is not null and not exists(
    select 1 from audience.segment_snapshots ss join audience.segments s on s.id=ss.segment_id
    where ss.id=v_experiment.segment_snapshot_id and s.segment_key=v_experiment.segment_key
      and s.status='Active' and ss.segment_version=s.version
  ) then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_segment_snapshot_stale','message','Target segment changed after experiment review. Create a fresh audience snapshot.','replayed',false);
  else
    select coalesce(sum(weight_basis_points),0) into v_total from analytics.experiment_variants where experiment_key=p_experiment_key;
    if p_status in ('Scheduled','Running') and v_total<>10000 then
      v_response:=jsonb_build_object('httpStatus',409,'code','experiment_variant_weights_invalid','message','Variant weights must total 10000 before launch.','replayed',false);
    elsif p_status='Running' and v_experiment.starts_at_utc is not null and v_experiment.starts_at_utc>now() then
      v_response:=jsonb_build_object('httpStatus',409,'code','experiment_window_not_started','message','Experiment start time has not arrived.','replayed',false);
    elsif p_status in ('Scheduled','Running') and v_experiment.ends_at_utc is not null and v_experiment.ends_at_utc<=now() then
      v_response:=jsonb_build_object('httpStatus',409,'code','experiment_window_elapsed','message','Experiment window has already elapsed.','replayed',false);
    else
      update analytics.experiments set status=p_status,version=version+1,updated_by_account_id=p_actor_account_id,updated_at_utc=now()
       where experiment_key=p_experiment_key returning * into v_experiment;
      v_response:=jsonb_build_object('httpStatus',200,'code','ok','experimentKey',p_experiment_key,'status',v_experiment.status,'version',v_experiment.version,'replayed',false);
    end if;
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'experiment',p_experiment_key,
    case when (v_response->>'httpStatus')::integer<400 then 'Succeeded' else 'Denied' end,
    case when (v_response->>'httpStatus')::integer<400 then trim(p_reason) else coalesce(v_response->>'message','Experiment status mutation denied.') end,
    p_correlation_id,p_idempotency_key,false,jsonb_build_object('requestedStatus',p_status,'version',v_response->>'version','code',v_response->>'code'));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

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
    'controlDefinitionVersion',e.control_definition_version,
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
    and c.version=e.control_definition_version
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

revoke all on function analytics.pin_experiment_control_version() from public;
revoke all on function admin.set_experiment_status(uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from public;
revoke all on function analytics.get_eligible_experiments(uuid,varchar) from public;
do $$ begin
  if to_regrole('anon') is not null then
    execute 'revoke all on function analytics.pin_experiment_control_version() from anon';
    execute 'revoke all on function admin.set_experiment_status(uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from anon';
    execute 'revoke all on function analytics.get_eligible_experiments(uuid,varchar) from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on function analytics.pin_experiment_control_version() from authenticated';
    execute 'revoke all on function admin.set_experiment_status(uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from authenticated';
    execute 'revoke all on function analytics.get_eligible_experiments(uuid,varchar) from authenticated';
  end if;
end $$;
grant execute on function admin.set_experiment_status(uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function analytics.get_eligible_experiments(uuid,varchar) to lifemate_edge_runtime;

comment on column analytics.experiments.control_definition_version is 'Pinned platform control definition version. Launch fails closed after control drift.';

commit;
