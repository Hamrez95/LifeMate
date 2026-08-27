begin;

create table if not exists analytics.experiments (
  experiment_key varchar(96) primary key,
  name varchar(160) not null check (length(trim(name)) between 3 and 160),
  control_key varchar(96) not null references platform.controls(control_key) on delete restrict,
  surface_code varchar(32) not null check (surface_code in ('onboarding','pricing','paywall','cta','offer','nonclinical_feature')),
  product_code varchar(64),
  segment_key varchar(96),
  primary_metric_code varchar(96) not null,
  guardrail_metric_codes varchar(96)[] not null default '{}',
  status varchar(16) not null default 'Draft' check (status in ('Draft','Scheduled','Running','Paused','Stopped','Completed')),
  starts_at_utc timestamptz,
  ends_at_utc timestamptz,
  version bigint not null default 1 check (version >= 1),
  created_by_account_id uuid not null,
  updated_by_account_id uuid not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (experiment_key ~ '^[a-z][a-z0-9._-]{2,95}$'),
  check (product_code is null or product_code ~ '^[a-z0-9][a-z0-9._:-]{0,63}$'),
  check (segment_key is null or segment_key ~ '^[a-z0-9][a-z0-9._-]{0,95}$'),
  check (primary_metric_code ~ '^[a-z][a-z0-9._-]{2,95}$'),
  check (cardinality(guardrail_metric_codes) <= 8),
  check (not primary_metric_code = any(guardrail_metric_codes)),
  check (cardinality(guardrail_metric_codes) = cardinality(array(select distinct x from unnest(guardrail_metric_codes) x))),
  check (ends_at_utc is null or starts_at_utc is null or ends_at_utc > starts_at_utc)
);

create table if not exists analytics.experiment_variants (
  experiment_key varchar(96) not null references analytics.experiments(experiment_key) on delete cascade,
  variant_key varchar(96) not null,
  weight_basis_points integer not null check (weight_basis_points between 1 and 10000),
  control_value jsonb not null,
  version bigint not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  primary key (experiment_key,variant_key),
  check (variant_key ~ '^[a-z][a-z0-9._-]{2,95}$'),
  check (octet_length(control_value::text) <= 4096)
);

create table if not exists analytics.experiment_exposures (
  id uuid primary key default gen_random_uuid(),
  experiment_key varchar(96) not null references analytics.experiments(experiment_key) on delete restrict,
  experiment_version bigint not null check (experiment_version >= 1),
  variant_key varchar(96) not null,
  variant_version bigint not null check (variant_version >= 1),
  idempotency_hash char(64) not null check (idempotency_hash ~ '^[0-9a-f]{64}$'),
  occurred_at_utc timestamptz not null,
  recorded_at_utc timestamptz not null default now(),
  metadata_json jsonb not null default '{}'::jsonb,
  unique(experiment_key,idempotency_hash),
  check (octet_length(metadata_json::text) <= 2048),
  foreign key (experiment_key,variant_key) references analytics.experiment_variants(experiment_key,variant_key) on delete restrict
);

create index if not exists ix_analytics_experiments_status_window
  on analytics.experiments(status,starts_at_utc,ends_at_utc,experiment_key);
create index if not exists ix_analytics_experiment_exposures_status
  on analytics.experiment_exposures(experiment_key,occurred_at_utc,variant_key);

alter table analytics.experiments enable row level security;
alter table analytics.experiment_variants enable row level security;
alter table analytics.experiment_exposures enable row level security;
alter table analytics.experiments force row level security;
alter table analytics.experiment_variants force row level security;
alter table analytics.experiment_exposures force row level security;

drop policy if exists experiments_admin_read on analytics.experiments;
create policy experiments_admin_read on analytics.experiments for select to lifemate_admin_runtime using(true);
drop policy if exists experiment_variants_admin_read on analytics.experiment_variants;
create policy experiment_variants_admin_read on analytics.experiment_variants for select to lifemate_admin_runtime using(true);
drop policy if exists experiment_exposures_admin_read on analytics.experiment_exposures;
create policy experiment_exposures_admin_read on analytics.experiment_exposures for select to lifemate_admin_runtime using(true);

revoke all on analytics.experiments,analytics.experiment_variants,analytics.experiment_exposures from public;
do $$ begin
  if to_regrole('anon') is not null then execute 'revoke all on analytics.experiments,analytics.experiment_variants,analytics.experiment_exposures from anon'; end if;
  if to_regrole('authenticated') is not null then execute 'revoke all on analytics.experiments,analytics.experiment_variants,analytics.experiment_exposures from authenticated'; end if;
  if to_regrole('lifemate_edge_runtime') is not null then execute 'revoke all on analytics.experiments,analytics.experiment_variants,analytics.experiment_exposures from lifemate_edge_runtime'; end if;
end $$;
grant select on analytics.experiments,analytics.experiment_variants,analytics.experiment_exposures to lifemate_admin_runtime;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('experiments.read','experiments','STANDARD',true,'Read canonical experiment definitions, rollout state and aggregate exposure metadata'),
('experiments.write','experiments','HIGH_RISK',true,'Create, schedule, pause, stop and complete non-clinical product experiments')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code from admin.roles r cross join admin.permissions p
where r.code in ('founder','super_admin') and p.code in ('experiments.read','experiments.write')
on conflict do nothing;
insert into admin.role_permissions(role_id,permission_code)
select r.id,'experiments.read' from admin.roles r where r.code in ('product','marketing','technical')
on conflict do nothing;
insert into admin.role_permissions(role_id,permission_code)
select r.id,'experiments.write' from admin.roles r where r.code in ('product','technical')
on conflict do nothing;

create or replace function admin.create_experiment(
  p_actor_account_id uuid,
  p_experiment_key varchar,
  p_name varchar,
  p_control_key varchar,
  p_surface_code varchar,
  p_product_code varchar,
  p_segment_key varchar,
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
set search_path=pg_catalog,analytics,platform,admin,pg_temp
as $$
declare
  v_existing admin.idempotency_keys%rowtype;
  v_response jsonb;
  v_variant jsonb;
  v_weight_total integer:=0;
  v_variant_count integer:=0;
  v_operation varchar(160):='experiments.create';
begin
  if not admin.account_has_permission(p_actor_account_id,'experiments.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_experiment_key is null or p_experiment_key !~ '^[a-z][a-z0-9._-]{2,95}$'
     or p_name is null or length(trim(p_name)) not between 3 and 160
     or p_control_key is null or p_control_key !~ '^[a-z][a-z0-9._-]{2,95}$'
     or p_surface_code not in ('onboarding','pricing','paywall','cta','offer','nonclinical_feature') then
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
  if not exists(select 1 from platform.controls where control_key=p_control_key and status='Active') then
    return jsonb_build_object('httpStatus',409,'code','experiment_control_unavailable','message','Experiment control must reference an active platform control.','replayed',false);
  end if;
  if jsonb_typeof(p_variants)<>'array' or jsonb_array_length(p_variants) not between 2 and 10 then
    return jsonb_build_object('httpStatus',400,'code','experiment_variants_invalid','message','Experiment variants are invalid.','replayed',false);
  end if;
  for v_variant in select value from jsonb_array_elements(p_variants) loop
    if coalesce(v_variant->>'key','') !~ '^[a-z][a-z0-9._-]{2,95}$'
       or coalesce((v_variant->>'weightBasisPoints')::integer,0) not between 1 and 10000
       or not (v_variant ? 'controlValue') then
      return jsonb_build_object('httpStatus',400,'code','experiment_variant_invalid','message','Experiment variant is invalid.','replayed',false);
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
      experiment_key,name,control_key,surface_code,product_code,segment_key,primary_metric_code,
      guardrail_metric_codes,status,starts_at_utc,ends_at_utc,created_by_account_id,updated_by_account_id
    ) values(
      p_experiment_key,trim(p_name),p_control_key,p_surface_code,nullif(trim(p_product_code),''),nullif(trim(p_segment_key),''),
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
    jsonb_build_object('surface',p_surface_code,'productCode',p_product_code,'segmentKey',p_segment_key,'primaryMetricCode',p_primary_metric_code,'variantCount',v_variant_count,'code',v_response->>'code'));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

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
set search_path=pg_catalog,analytics,platform,admin,pg_temp
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
  elsif p_status='Running' and not exists(select 1 from platform.controls where control_key=v_experiment.control_key and status='Active') then
    v_response:=jsonb_build_object('httpStatus',409,'code','experiment_control_unavailable','message','Experiment control is not active.','replayed',false);
  else
    select coalesce(sum(weight_basis_points),0) into v_total from analytics.experiment_variants where experiment_key=p_experiment_key;
    if p_status in ('Scheduled','Running') and v_total<>10000 then
      v_response:=jsonb_build_object('httpStatus',409,'code','experiment_variant_weights_invalid','message','Variant weights must total 10000 before launch.','replayed',false);
    elsif p_status='Running' and (v_experiment.ends_at_utc is not null and v_experiment.ends_at_utc<=now()) then
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

create or replace function analytics.record_experiment_exposure(
  p_experiment_key varchar,
  p_experiment_version bigint,
  p_variant_key varchar,
  p_variant_version bigint,
  p_idempotency_hash char(64),
  p_occurred_at_utc timestamptz,
  p_metadata_json jsonb default '{}'::jsonb
) returns boolean
language plpgsql
security definer
set search_path=pg_catalog,analytics,pg_temp
as $$
declare
  v_experiment analytics.experiments%rowtype;
begin
  if p_idempotency_hash is null or p_idempotency_hash !~ '^[0-9a-f]{64}$'
     or p_occurred_at_utc is null
     or p_metadata_json is null or octet_length(p_metadata_json::text)>2048 then
    return false;
  end if;
  select * into v_experiment from analytics.experiments where experiment_key=p_experiment_key;
  if not found or v_experiment.status<>'Running' or v_experiment.version<>p_experiment_version
     or (v_experiment.starts_at_utc is not null and p_occurred_at_utc<v_experiment.starts_at_utc)
     or (v_experiment.ends_at_utc is not null and p_occurred_at_utc>=v_experiment.ends_at_utc)
     or not exists(select 1 from analytics.experiment_variants where experiment_key=p_experiment_key and variant_key=p_variant_key and version=p_variant_version) then
    return false;
  end if;
  insert into analytics.experiment_exposures(experiment_key,experiment_version,variant_key,variant_version,idempotency_hash,occurred_at_utc,metadata_json)
  values(p_experiment_key,p_experiment_version,p_variant_key,p_variant_version,p_idempotency_hash,p_occurred_at_utc,p_metadata_json)
  on conflict(experiment_key,idempotency_hash) do nothing;
  return true;
end $$;

revoke all on function admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar) from public;
revoke all on function admin.set_experiment_status(uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from public;
revoke all on function analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,char,timestamptz,jsonb) from public;
do $$ begin
  if to_regrole('anon') is not null then
    execute 'revoke all on function admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar) from anon';
    execute 'revoke all on function admin.set_experiment_status(uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from anon';
    execute 'revoke all on function analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,char,timestamptz,jsonb) from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on function admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar) from authenticated';
    execute 'revoke all on function admin.set_experiment_status(uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from authenticated';
    execute 'revoke all on function analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,char,timestamptz,jsonb) from authenticated';
  end if;
end $$;
grant execute on function admin.create_experiment(uuid,varchar,varchar,varchar,varchar,varchar,varchar,varchar,varchar[],jsonb,timestamptz,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.set_experiment_status(uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function analytics.record_experiment_exposure(varchar,bigint,varchar,bigint,char,timestamptz,jsonb) to lifemate_admin_runtime,lifemate_edge_runtime;

comment on table analytics.experiments is 'Non-clinical A/B experiment definitions delivered through canonical platform controls. No PII or health payload is stored.';
comment on table analytics.experiment_exposures is 'Privacy-minimized exposure facts. Idempotency hashes are event deduplication keys, not user identifiers.';
comment on function analytics.record_experiment_exposure is 'Server-runtime exposure recorder; no direct browser table access and no subject identifier persisted.';

commit;
