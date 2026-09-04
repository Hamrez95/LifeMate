begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('security.retention.read','security','SENSITIVE',true,'Read data lifecycle policies, deletion queue state and preservation holds'),
('security.retention.write','security','ELEVATED',false,'Change retention policies and preservation holds')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,'security.retention.read'
from admin.roles r
where r.code in ('founder','super_admin','security','operations')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'security.retention.write'
from admin.roles r
where r.code in ('founder','super_admin','security')
on conflict do nothing;

alter table security.retention_policies
  add column if not exists grace_days integer not null default 0 check (grace_days between 0 and 3650),
  add column if not exists version bigint not null default 1 check (version >= 1);

create table if not exists security.retention_policy_versions (
  id uuid primary key default gen_random_uuid(),
  data_category character varying(80) not null,
  purpose_code character varying(80) not null default 'default',
  retention_days integer check (retention_days is null or retention_days between 0 and 36500),
  grace_days integer not null default 0 check (grace_days between 0 and 3650),
  disposition character varying(24) not null check (disposition in ('Delete','Anonymize','Archive','Review')),
  policy_version bigint not null check (policy_version >= 1),
  status character varying(16) not null default 'Draft' check (status in ('Draft','Active','Retired')),
  legal_basis character varying(500),
  effective_at_utc timestamptz,
  created_by_account_id uuid,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  unique(data_category,purpose_code,policy_version)
);
create unique index if not exists ux_security_retention_policy_versions_active
  on security.retention_policy_versions(data_category,purpose_code)
  where status='Active';
create index if not exists ix_security_retention_policy_versions_lookup
  on security.retention_policy_versions(data_category,purpose_code,status,policy_version desc);

insert into security.retention_policy_versions(
  data_category,purpose_code,retention_days,grace_days,disposition,policy_version,status,legal_basis,effective_at_utc,created_at_utc,updated_at_utc
)
select p.data_category,'default',p.retention_days,p.grace_days,p.disposition,p.version,'Active',p.legal_basis,p.updated_at_utc,p.updated_at_utc,p.updated_at_utc
from security.retention_policies p
where not exists (
  select 1 from security.retention_policy_versions v
  where v.data_category=p.data_category and v.purpose_code='default' and v.status='Active'
);

create table if not exists security.retention_holds (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references identity.accounts(id) on delete cascade,
  data_category character varying(80),
  purpose_code character varying(80),
  reason_code character varying(80) not null,
  reason character varying(1000) not null check (length(trim(reason)) between 10 and 1000),
  status character varying(16) not null default 'Active' check (status in ('Active','Released','Expired')),
  expires_at_utc timestamptz,
  created_by_account_id uuid not null,
  created_at_utc timestamptz not null default now(),
  released_by_account_id uuid,
  released_at_utc timestamptz,
  release_reason character varying(1000),
  check (expires_at_utc is null or expires_at_utc > created_at_utc),
  check ((status='Released') = (released_at_utc is not null))
);
create index if not exists ix_security_retention_holds_account_active
  on security.retention_holds(account_id,status,expires_at_utc);

create table if not exists security.retention_execution_runs (
  id uuid primary key default gen_random_uuid(),
  mode character varying(16) not null check (mode in ('Preview','Purge')),
  status character varying(24) not null default 'Pending' check (status in ('Pending','Running','Completed','Failed','Cancelled')),
  data_category character varying(80),
  purpose_code character varying(80),
  policy_version bigint,
  cursor_json jsonb not null default '{}'::jsonb check (jsonb_typeof(cursor_json)='object'),
  candidate_count bigint not null default 0 check (candidate_count >= 0),
  processed_count bigint not null default 0 check (processed_count >= 0),
  deleted_count bigint not null default 0 check (deleted_count >= 0),
  anonymized_count bigint not null default 0 check (anonymized_count >= 0),
  held_count bigint not null default 0 check (held_count >= 0),
  error_count bigint not null default 0 check (error_count >= 0),
  initiated_by_account_id uuid not null,
  correlation_id uuid not null,
  started_at_utc timestamptz,
  completed_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);
create index if not exists ix_security_retention_runs_status
  on security.retention_execution_runs(status,created_at_utc desc);

alter table identity.account_deletion_requests
  add column if not exists eligible_at_utc timestamptz,
  add column if not exists last_attempt_at_utc timestamptz,
  add column if not exists next_attempt_at_utc timestamptz,
  add column if not exists attempt_count integer not null default 0 check (attempt_count >= 0),
  add column if not exists execution_cursor_json jsonb not null default '{}'::jsonb check (jsonb_typeof(execution_cursor_json)='object');

update identity.account_deletion_requests
set eligible_at_utc=coalesce(eligible_at_utc,requested_at_utc)
where eligible_at_utc is null;

alter table security.retention_policy_versions enable row level security;
alter table security.retention_policy_versions force row level security;
alter table security.retention_holds enable row level security;
alter table security.retention_holds force row level security;
alter table security.retention_execution_runs enable row level security;
alter table security.retention_execution_runs force row level security;

revoke all on table security.retention_policy_versions from public,anon,authenticated;
revoke all on table security.retention_holds from public,anon,authenticated;
revoke all on table security.retention_execution_runs from public,anon,authenticated;

grant select,insert,update on security.retention_policy_versions to lifemate_admin_runtime;
grant select,insert,update on security.retention_holds to lifemate_admin_runtime;
grant select,insert,update on security.retention_execution_runs to lifemate_admin_runtime;
grant select on security.retention_holds to lifemate_worker_runtime;
grant select,update on identity.account_deletion_requests to lifemate_worker_runtime;

drop policy if exists retention_policy_versions_admin_runtime on security.retention_policy_versions;
drop policy if exists retention_holds_admin_runtime on security.retention_holds;
drop policy if exists retention_holds_worker_runtime on security.retention_holds;
drop policy if exists retention_execution_runs_admin_runtime on security.retention_execution_runs;

create policy retention_policy_versions_admin_runtime on security.retention_policy_versions
  for all to lifemate_admin_runtime using (true) with check (true);
create policy retention_holds_admin_runtime on security.retention_holds
  for all to lifemate_admin_runtime using (true) with check (true);
create policy retention_holds_worker_runtime on security.retention_holds
  for select to lifemate_worker_runtime using (true);
create policy retention_execution_runs_admin_runtime on security.retention_execution_runs
  for all to lifemate_admin_runtime using (true) with check (true);

create or replace function security.retention_policy_for(
  p_data_category character varying,
  p_purpose_code character varying default 'default'
) returns table(
  data_category character varying,
  purpose_code character varying,
  retention_days integer,
  grace_days integer,
  disposition character varying,
  policy_version bigint,
  legal_basis character varying
)
language sql
stable
security invoker
set search_path=security,pg_temp
as $$
  select v.data_category,v.purpose_code,v.retention_days,v.grace_days,v.disposition,v.policy_version,v.legal_basis
  from security.retention_policy_versions v
  where v.data_category=lower(trim(p_data_category))
    and v.purpose_code=lower(trim(coalesce(nullif(p_purpose_code,''),'default')))
    and v.status='Active'
  order by v.policy_version desc
  limit 1
$$;

create or replace function security.activate_retention_policy(
  p_actor_account_id uuid,
  p_data_category character varying,
  p_purpose_code character varying,
  p_retention_days integer,
  p_grace_days integer,
  p_disposition character varying,
  p_legal_basis character varying,
  p_reason character varying,
  p_correlation_id uuid
) returns jsonb
language plpgsql
set search_path=security,admin,pg_temp
as $$
declare
  v_category character varying(80):=lower(trim(coalesce(p_data_category,'')));
  v_purpose character varying(80):=lower(trim(coalesce(nullif(p_purpose_code,''),'default')));
  v_disposition character varying(24):=initcap(lower(trim(coalesce(p_disposition,''))));
  v_next_version bigint;
  v_id uuid;
begin
  if not admin.account_has_permission(p_actor_account_id,'security.retention.write') then
    return jsonb_build_object('httpStatus',403,'code','retention_permission_denied','message','Actor cannot change retention policy.');
  end if;
  if v_category !~ '^[a-z][a-z0-9._-]{2,79}$' or v_purpose !~ '^[a-z][a-z0-9._-]{2,79}$' then
    return jsonb_build_object('httpStatus',400,'code','retention_policy_key_invalid','message','Retention policy category or purpose is invalid.');
  end if;
  if p_retention_days is not null and (p_retention_days<0 or p_retention_days>36500) then
    return jsonb_build_object('httpStatus',400,'code','retention_days_invalid','message','retentionDays is outside the allowed range.');
  end if;
  if p_grace_days is null or p_grace_days<0 or p_grace_days>3650 then
    return jsonb_build_object('httpStatus',400,'code','retention_grace_invalid','message','graceDays is outside the allowed range.');
  end if;
  if v_disposition not in ('Delete','Anonymize','Archive','Review') then
    return jsonb_build_object('httpStatus',400,'code','retention_disposition_invalid','message','Disposition is invalid.');
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','retention_reason_invalid','message','A bounded change reason is required.');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_category||':'||v_purpose,0));
  select coalesce(max(policy_version),0)+1 into v_next_version
  from security.retention_policy_versions
  where data_category=v_category and purpose_code=v_purpose;

  update security.retention_policy_versions
  set status='Retired',updated_at_utc=now()
  where data_category=v_category and purpose_code=v_purpose and status='Active';

  insert into security.retention_policy_versions(
    data_category,purpose_code,retention_days,grace_days,disposition,policy_version,status,
    legal_basis,effective_at_utc,created_by_account_id
  ) values(
    v_category,v_purpose,p_retention_days,p_grace_days,v_disposition,v_next_version,'Active',
    nullif(trim(coalesce(p_legal_basis,'')),''),now(),p_actor_account_id
  ) returning id into v_id;

  if v_purpose='default' then
    insert into security.retention_policies(data_category,retention_days,disposition,policy_version,legal_basis,updated_at_utc,grace_days,version)
    values(v_category,p_retention_days,v_disposition,'retention-v3.'||v_next_version::text,nullif(trim(coalesce(p_legal_basis,'')),''),now(),p_grace_days,v_next_version)
    on conflict(data_category) do update set
      retention_days=excluded.retention_days,
      disposition=excluded.disposition,
      policy_version=excluded.policy_version,
      legal_basis=excluded.legal_basis,
      updated_at_utc=excluded.updated_at_utc,
      grace_days=excluded.grace_days,
      version=excluded.version;
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'security.retention.policy.activate','retention_policy',v_id::text,'Succeeded',trim(p_reason),p_correlation_id,true,
    jsonb_build_object('dataCategory',v_category,'purposeCode',v_purpose,'policyVersion',v_next_version,'disposition',v_disposition));

  return jsonb_build_object('httpStatus',200,'code','ok','id',v_id,'dataCategory',v_category,'purposeCode',v_purpose,'policyVersion',v_next_version);
end $$;

create or replace function security.create_retention_hold(
  p_actor_account_id uuid,
  p_account_id uuid,
  p_data_category character varying,
  p_purpose_code character varying,
  p_reason_code character varying,
  p_reason character varying,
  p_expires_at_utc timestamptz,
  p_correlation_id uuid
) returns jsonb
language plpgsql
set search_path=security,admin,identity,pg_temp
as $$
declare v_id uuid;
begin
  if not admin.account_has_permission(p_actor_account_id,'security.retention.write') then
    return jsonb_build_object('httpStatus',403,'code','retention_permission_denied','message','Actor cannot create preservation holds.');
  end if;
  if not exists(select 1 from identity.accounts where id=p_account_id) then
    return jsonb_build_object('httpStatus',404,'code','retention_account_not_found','message','Account was not found.');
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000
     or p_reason_code is null or p_reason_code !~ '^[a-z][a-z0-9._-]{2,79}$' then
    return jsonb_build_object('httpStatus',400,'code','retention_hold_reason_invalid','message','A valid reason code and bounded reason are required.');
  end if;
  if p_expires_at_utc is not null and p_expires_at_utc<=now() then
    return jsonb_build_object('httpStatus',400,'code','retention_hold_expiry_invalid','message','Hold expiry must be in the future.');
  end if;

  insert into security.retention_holds(account_id,data_category,purpose_code,reason_code,reason,status,expires_at_utc,created_by_account_id)
  values(p_account_id,nullif(lower(trim(coalesce(p_data_category,''))),''),nullif(lower(trim(coalesce(p_purpose_code,''))),''),lower(trim(p_reason_code)),trim(p_reason),'Active',p_expires_at_utc,p_actor_account_id)
  returning id into v_id;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'security.retention.hold.create','retention_hold',v_id::text,'Succeeded',trim(p_reason),p_correlation_id,true,
    jsonb_build_object('accountId',p_account_id,'reasonCode',lower(trim(p_reason_code))));
  return jsonb_build_object('httpStatus',201,'code','ok','id',v_id);
end $$;

create or replace function security.release_retention_hold(
  p_actor_account_id uuid,
  p_hold_id uuid,
  p_reason character varying,
  p_correlation_id uuid
) returns jsonb
language plpgsql
set search_path=security,admin,pg_temp
as $$
declare v_hold security.retention_holds%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'security.retention.write') then
    return jsonb_build_object('httpStatus',403,'code','retention_permission_denied','message','Actor cannot release preservation holds.');
  end if;
  select * into v_hold from security.retention_holds where id=p_hold_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','retention_hold_not_found','message','Hold was not found.'); end if;
  if v_hold.status<>'Active' then return jsonb_build_object('httpStatus',409,'code','retention_hold_not_active','message','Hold is no longer active.'); end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','retention_reason_invalid','message','A bounded release reason is required.');
  end if;
  update security.retention_holds set status='Released',released_by_account_id=p_actor_account_id,released_at_utc=now(),release_reason=trim(p_reason) where id=p_hold_id;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'security.retention.hold.release','retention_hold',p_hold_id::text,'Succeeded',trim(p_reason),p_correlation_id,true,'{}'::jsonb);
  return jsonb_build_object('httpStatus',200,'code','ok','id',p_hold_id);
end $$;

create or replace function identity.account_deletion_execution_eligibility(p_request_id uuid)
returns table(eligible boolean,code character varying,next_eligible_at_utc timestamptz)
language plpgsql
security definer
set search_path=pg_catalog,identity,security,pg_temp
as $$
declare
  v_request identity.account_deletion_requests%rowtype;
  v_hold_until timestamptz;
begin
  select * into v_request from identity.account_deletion_requests where id=p_request_id for update;
  if not found then
    return query select false,'deletion_request_not_found'::varchar,null::timestamptz; return;
  end if;
  if v_request.status='Completed' then
    return query select false,'deletion_already_completed'::varchar,null::timestamptz; return;
  end if;
  if v_request.status not in ('Requested','Processing') then
    return query select false,'deletion_request_not_processable'::varchar,null::timestamptz; return;
  end if;

  update security.retention_holds set status='Expired'
  where account_id=v_request.account_id and status='Active' and expires_at_utc is not null and expires_at_utc<=now();

  select max(expires_at_utc) into v_hold_until
  from security.retention_holds
  where account_id=v_request.account_id and status='Active';
  if exists(select 1 from security.retention_holds where account_id=v_request.account_id and status='Active' and expires_at_utc is null) then
    return query select false,'retention_hold_active'::varchar,null::timestamptz; return;
  end if;
  if v_hold_until is not null and v_hold_until>now() then
    return query select false,'retention_hold_active'::varchar,v_hold_until; return;
  end if;
  if coalesce(v_request.eligible_at_utc,v_request.requested_at_utc)>now() then
    return query select false,'deletion_grace_active'::varchar,coalesce(v_request.eligible_at_utc,v_request.requested_at_utc); return;
  end if;

  update identity.account_deletion_requests
  set last_attempt_at_utc=now(),attempt_count=attempt_count+1,next_attempt_at_utc=null
  where id=p_request_id;
  return query select true,'eligible'::varchar,null::timestamptz;
end $$;

revoke all on function security.retention_policy_for(character varying,character varying) from public;
revoke all on function security.activate_retention_policy(uuid,character varying,character varying,integer,integer,character varying,character varying,character varying,uuid) from public;
revoke all on function security.create_retention_hold(uuid,uuid,character varying,character varying,character varying,character varying,timestamptz,uuid) from public;
revoke all on function security.release_retention_hold(uuid,uuid,character varying,uuid) from public;
revoke all on function identity.account_deletion_execution_eligibility(uuid) from public;
grant execute on function security.retention_policy_for(character varying,character varying) to lifemate_admin_runtime,lifemate_worker_runtime;
grant execute on function security.activate_retention_policy(uuid,character varying,character varying,integer,integer,character varying,character varying,character varying,uuid) to lifemate_admin_runtime;
grant execute on function security.create_retention_hold(uuid,uuid,character varying,character varying,character varying,character varying,timestamptz,uuid) to lifemate_admin_runtime;
grant execute on function security.release_retention_hold(uuid,uuid,character varying,uuid) to lifemate_admin_runtime;
grant execute on function identity.account_deletion_execution_eligibility(uuid) to lifemate_worker_runtime;

commit;