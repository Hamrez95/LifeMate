begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('operations.approval.read','operations','SENSITIVE',true,'Read high-risk administrative approval requests and immutable decision history')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,'operations.approval.read'
from admin.roles r
where r.code in ('founder','super_admin','security')
on conflict do nothing;

create table if not exists admin.approval_policies (
  request_type character varying(80) primary key,
  display_name character varying(160) not null,
  request_permission character varying(128) not null references admin.permissions(code) on delete restrict,
  approval_permission character varying(128) not null references admin.permissions(code) on delete restrict,
  execution_permission character varying(128) not null references admin.permissions(code) on delete restrict,
  self_approval_allowed boolean not null default false,
  default_expiry_minutes integer not null default 1440 check (default_expiry_minutes between 5 and 43200),
  status character varying(24) not null default 'Active' check (status in ('Active','Disabled')),
  version bigint not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);

create table if not exists admin.approval_policy_approver_roles (
  request_type character varying(80) not null references admin.approval_policies(request_type) on delete cascade,
  role_code character varying(64) not null references admin.roles(code) on delete restrict,
  created_at_utc timestamptz not null default now(),
  primary key(request_type,role_code)
);

create table if not exists admin.approval_requests (
  id uuid primary key default gen_random_uuid(),
  request_type character varying(80) not null references admin.approval_policies(request_type) on delete restrict,
  target_type character varying(80) not null,
  target_id character varying(180) not null,
  before_json jsonb not null default '{}'::jsonb check (jsonb_typeof(before_json)='object'),
  requested_delta_json jsonb not null default '{}'::jsonb check (jsonb_typeof(requested_delta_json)='object'),
  after_json jsonb not null default '{}'::jsonb check (jsonb_typeof(after_json)='object'),
  reason character varying(1000) not null check (length(trim(reason)) between 10 and 1000),
  requester_account_id uuid not null,
  status character varying(24) not null default 'Pending'
    check (status in ('Pending','Approved','Rejected','Expired','Executed','Cancelled')),
  version bigint not null default 1 check (version >= 1),
  expires_at_utc timestamptz not null,
  reviewed_by_account_id uuid,
  reviewed_at_utc timestamptz,
  review_reason character varying(1000),
  executed_by_account_id uuid,
  execution_correlation_id uuid,
  executed_at_utc timestamptz,
  execution_operation character varying(160),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (expires_at_utc > created_at_utc)
);
create index if not exists ix_admin_approval_requests_status_expiry
  on admin.approval_requests(status,expires_at_utc,created_at_utc desc);
create index if not exists ix_admin_approval_requests_requester
  on admin.approval_requests(requester_account_id,created_at_utc desc);
create index if not exists ix_admin_approval_requests_target
  on admin.approval_requests(target_type,target_id,created_at_utc desc);

create table if not exists admin.approval_events (
  id uuid primary key default gen_random_uuid(),
  approval_request_id uuid not null references admin.approval_requests(id) on delete restrict,
  actor_account_id uuid not null,
  event_type character varying(32) not null
    check (event_type in ('Requested','Approved','Rejected','Expired','Executed','Cancelled')),
  from_status character varying(24),
  to_status character varying(24) not null,
  reason character varying(1000),
  correlation_id uuid not null,
  metadata_json jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata_json)='object'),
  occurred_at_utc timestamptz not null default now()
);
create index if not exists ix_admin_approval_events_request
  on admin.approval_events(approval_request_id,occurred_at_utc,id);

alter table admin.approval_policies enable row level security;
alter table admin.approval_policies force row level security;
alter table admin.approval_policy_approver_roles enable row level security;
alter table admin.approval_policy_approver_roles force row level security;
alter table admin.approval_requests enable row level security;
alter table admin.approval_requests force row level security;
alter table admin.approval_events enable row level security;
alter table admin.approval_events force row level security;

revoke all on table admin.approval_policies from public,anon,authenticated;
revoke all on table admin.approval_policy_approver_roles from public,anon,authenticated;
revoke all on table admin.approval_requests from public,anon,authenticated;
revoke all on table admin.approval_events from public,anon,authenticated;

grant select on admin.approval_policies to lifemate_admin_runtime;
grant select on admin.approval_policy_approver_roles to lifemate_admin_runtime;
grant select,insert,update on admin.approval_requests to lifemate_admin_runtime;
grant select,insert on admin.approval_events to lifemate_admin_runtime;

create or replace function admin.approval_actor_is_eligible_approver(
  p_actor_account_id uuid,
  p_request_type character varying,
  p_at timestamptz default now()
) returns boolean
language sql
stable
set search_path=admin,pg_temp
as $$
  select exists(
    select 1
    from admin.members m
    join admin.member_roles mr on mr.account_id=m.account_id
    join admin.roles r on r.id=mr.role_id
    join admin.approval_policy_approver_roles ar on ar.role_code=r.code
    where m.account_id=p_actor_account_id
      and m.status='Active'
      and r.status='Active'
      and mr.revoked_at_utc is null
      and mr.starts_at_utc<=p_at
      and (mr.expires_at_utc is null or mr.expires_at_utc>p_at)
      and ar.request_type=p_request_type
  )
$$;

create or replace function admin.create_approval_request(
  p_actor_account_id uuid,
  p_request_type character varying,
  p_target_type character varying,
  p_target_id character varying,
  p_before_json jsonb,
  p_requested_delta_json jsonb,
  p_after_json jsonb,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path=admin,pg_temp
as $$
declare
  v_type character varying(80):=lower(trim(coalesce(p_request_type,'')));
  v_operation character varying(160):='operations.approval.request:' || v_type;
  v_policy admin.approval_policies%rowtype;
  v_existing admin.idempotency_keys%rowtype;
  v_request admin.approval_requests%rowtype;
  v_response jsonb;
begin
  select * into v_policy from admin.approval_policies where request_type=v_type;
  if v_policy.request_type is null or v_policy.status<>'Active' then
    return jsonb_build_object('httpStatus',404,'code','approval_policy_unavailable','message','Approval policy is unavailable.','replayed',false);
  end if;
  if not admin.account_has_permission(p_actor_account_id,v_policy.request_permission) then
    return jsonb_build_object('httpStatus',403,'code','approval_request_permission_denied','message','Actor cannot request this operation.','replayed',false);
  end if;
  if p_target_type is null or length(trim(p_target_type))<2 or length(trim(p_target_type))>80
     or p_target_id is null or length(trim(p_target_id))<1 or length(trim(p_target_id))>180 then
    return jsonb_build_object('httpStatus',400,'code','approval_target_invalid','message','Approval target is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','approval_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if coalesce(jsonb_typeof(p_before_json),'null')<>'object'
     or coalesce(jsonb_typeof(p_requested_delta_json),'null')<>'object'
     or coalesce(jsonb_typeof(p_after_json),'null')<>'object' then
    return jsonb_build_object('httpStatus',400,'code','approval_delta_invalid','message','Before, delta and after values must be JSON objects.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  insert into admin.approval_requests(
    request_type,target_type,target_id,before_json,requested_delta_json,after_json,reason,
    requester_account_id,status,expires_at_utc
  ) values(
    v_type,trim(p_target_type),trim(p_target_id),p_before_json,p_requested_delta_json,p_after_json,trim(p_reason),
    p_actor_account_id,'Pending',now() + make_interval(mins=>v_policy.default_expiry_minutes)
  ) returning * into v_request;

  insert into admin.approval_events(approval_request_id,actor_account_id,event_type,to_status,reason,correlation_id,metadata_json)
  values(v_request.id,p_actor_account_id,'Requested','Pending',trim(p_reason),p_correlation_id,
    jsonb_build_object('requestType',v_type,'targetType',v_request.target_type,'targetId',v_request.target_id,'policyVersion',v_policy.version));
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,'operations.approval.request','approval_request',v_request.id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('requestType',v_type,'targetType',v_request.target_type,'targetId',v_request.target_id,'version',v_request.version));

  v_response:=jsonb_build_object(
    'httpStatus',201,'code','ok','id',v_request.id,'requestType',v_request.request_type,
    'status',v_request.status,'version',v_request.version,'expiresAtUtc',v_request.expires_at_utc,'replayed',false
  );
  update admin.idempotency_keys set status='Completed',response_status=201,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function admin.decide_approval_request(
  p_actor_account_id uuid,
  p_request_id uuid,
  p_expected_version bigint,
  p_decision character varying,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path=admin,pg_temp
as $$
declare
  v_decision character varying(16):=lower(trim(coalesce(p_decision,'')));
  v_operation character varying(160):='operations.approval.' || v_decision;
  v_request admin.approval_requests%rowtype;
  v_policy admin.approval_policies%rowtype;
  v_existing admin.idempotency_keys%rowtype;
  v_status character varying(24);
  v_event character varying(32);
  v_response jsonb;
begin
  if v_decision not in ('approve','reject') then
    return jsonb_build_object('httpStatus',400,'code','approval_decision_invalid','message','Decision must be approve or reject.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','approval_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_expected_version is null or p_expected_version<1 then
    return jsonb_build_object('httpStatus',400,'code','approval_version_invalid','message','expectedVersion must be a positive integer.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  select * into v_request from admin.approval_requests where id=p_request_id for update;
  if v_request.id is null then
    v_response:=jsonb_build_object('httpStatus',404,'code','approval_request_not_found','message','Approval request was not found.','replayed',false);
  else
    select * into v_policy from admin.approval_policies where request_type=v_request.request_type;
    if v_policy.request_type is null or v_policy.status<>'Active' then
      v_response:=jsonb_build_object('httpStatus',409,'code','approval_policy_unavailable','message','Approval policy is unavailable.','replayed',false);
    elsif not admin.account_has_permission(p_actor_account_id,v_policy.approval_permission)
       or not admin.approval_actor_is_eligible_approver(p_actor_account_id,v_request.request_type) then
      v_response:=jsonb_build_object('httpStatus',403,'code','approval_decision_permission_denied','message','Actor is not an eligible approver for this request.','replayed',false);
    elsif not v_policy.self_approval_allowed and v_request.requester_account_id=p_actor_account_id then
      v_response:=jsonb_build_object('httpStatus',403,'code','approval_self_decision_denied','message','Self-approval is not permitted for this operation.','replayed',false);
    elsif v_request.version<>p_expected_version then
      v_response:=jsonb_build_object('httpStatus',409,'code','approval_version_conflict','message','Approval request changed; refresh before deciding.','currentVersion',v_request.version,'replayed',false);
    elsif v_request.status<>'Pending' then
      v_response:=jsonb_build_object('httpStatus',409,'code','approval_state_conflict','message','Only pending requests can be decided.','currentStatus',v_request.status,'replayed',false);
    elsif v_request.expires_at_utc<=now() then
      update admin.approval_requests set status='Expired',version=version+1,updated_at_utc=now() where id=v_request.id returning * into v_request;
      insert into admin.approval_events(approval_request_id,actor_account_id,event_type,from_status,to_status,reason,correlation_id)
      values(v_request.id,p_actor_account_id,'Expired','Pending','Expired','Request expired before decision.',p_correlation_id);
      v_response:=jsonb_build_object('httpStatus',409,'code','approval_request_expired','message','Approval request has expired.','currentVersion',v_request.version,'replayed',false);
    else
      v_status:=case when v_decision='approve' then 'Approved' else 'Rejected' end;
      v_event:=case when v_decision='approve' then 'Approved' else 'Rejected' end;
      update admin.approval_requests set status=v_status,version=version+1,reviewed_by_account_id=p_actor_account_id,
        reviewed_at_utc=now(),review_reason=trim(p_reason),updated_at_utc=now()
      where id=v_request.id returning * into v_request;
      insert into admin.approval_events(approval_request_id,actor_account_id,event_type,from_status,to_status,reason,correlation_id)
      values(v_request.id,p_actor_account_id,v_event,'Pending',v_status,trim(p_reason),p_correlation_id);
      insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
      values(p_actor_account_id,'operations.approval.'||v_decision,'approval_request',v_request.id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
        jsonb_build_object('requestType',v_request.request_type,'status',v_request.status,'version',v_request.version));
      v_response:=jsonb_build_object('httpStatus',200,'code','ok','id',v_request.id,'status',v_request.status,'version',v_request.version,'replayed',false);
    end if;
  end if;

  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function admin.consume_approval_request(
  p_actor_account_id uuid,
  p_request_id uuid,
  p_expected_version bigint,
  p_execution_operation character varying,
  p_correlation_id uuid
) returns jsonb
language plpgsql
set search_path=admin,pg_temp
as $$
declare
  v_request admin.approval_requests%rowtype;
  v_policy admin.approval_policies%rowtype;
begin
  if p_execution_operation is null or length(trim(p_execution_operation))<3 or length(trim(p_execution_operation))>160 then
    raise exception using errcode='22023',message='Execution operation is invalid.';
  end if;
  select * into v_request from admin.approval_requests where id=p_request_id for update;
  if v_request.id is null then
    raise exception using errcode='P0002',message='Approval request was not found.';
  end if;
  select * into v_policy from admin.approval_policies where request_type=v_request.request_type;
  if v_policy.request_type is null or v_policy.status<>'Active' then
    raise exception using errcode='55000',message='Approval policy is unavailable.';
  end if;
  if not admin.account_has_permission(p_actor_account_id,v_policy.execution_permission) then
    raise exception using errcode='42501',message='Actor cannot execute this approval request.';
  end if;
  if v_request.version<>p_expected_version then
    raise exception using errcode='40001',message='Approval request version conflict.';
  end if;
  if v_request.status<>'Approved' then
    raise exception using errcode='55000',message='Approval request is not approved.';
  end if;
  if v_request.expires_at_utc<=now() then
    raise exception using errcode='55000',message='Approval request has expired.';
  end if;

  update admin.approval_requests set status='Executed',version=version+1,executed_by_account_id=p_actor_account_id,
    execution_correlation_id=p_correlation_id,executed_at_utc=now(),execution_operation=trim(p_execution_operation),updated_at_utc=now()
  where id=v_request.id returning * into v_request;
  insert into admin.approval_events(approval_request_id,actor_account_id,event_type,from_status,to_status,reason,correlation_id,metadata_json)
  values(v_request.id,p_actor_account_id,'Executed','Approved','Executed','Consumed by purpose-specific execution.',p_correlation_id,
    jsonb_build_object('executionOperation',trim(p_execution_operation)));
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'operations.approval.execute','approval_request',v_request.id::text,'Succeeded','Consumed by purpose-specific execution.',p_correlation_id,false,
    jsonb_build_object('requestType',v_request.request_type,'executionOperation',trim(p_execution_operation),'version',v_request.version));

  return jsonb_build_object(
    'id',v_request.id,'requestType',v_request.request_type,'targetType',v_request.target_type,'targetId',v_request.target_id,
    'before',v_request.before_json,'delta',v_request.requested_delta_json,'after',v_request.after_json,
    'status',v_request.status,'version',v_request.version
  );
end $$;

revoke all on function admin.approval_actor_is_eligible_approver(uuid,character varying,timestamptz) from public,anon,authenticated;
revoke all on function admin.create_approval_request(uuid,character varying,character varying,character varying,jsonb,jsonb,jsonb,character varying,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function admin.decide_approval_request(uuid,uuid,bigint,character varying,character varying,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function admin.consume_approval_request(uuid,uuid,bigint,character varying,uuid) from public,anon,authenticated;
grant execute on function admin.approval_actor_is_eligible_approver(uuid,character varying,timestamptz) to lifemate_admin_runtime;
grant execute on function admin.create_approval_request(uuid,character varying,character varying,character varying,jsonb,jsonb,jsonb,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.decide_approval_request(uuid,uuid,bigint,character varying,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.consume_approval_request(uuid,uuid,bigint,character varying,uuid) to lifemate_admin_runtime;

comment on table admin.approval_policies is 'Purpose-scoped approval policy. Child domains register policies against their own request/approval/execution permissions.';
comment on function admin.consume_approval_request(uuid,uuid,bigint,character varying,uuid) is 'Must be called inside the same database transaction as the purpose-specific mutation. If that mutation fails, the consume transition must roll back with it.';
comment on column admin.approval_requests.requester_account_id is 'Audit provenance UUID only; deliberately no identity FK so workforce/account lifecycle does not destroy approval evidence.';

commit;
