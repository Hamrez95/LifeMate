-- Canonical, time-bound Command Center break-glass workflow.
-- This migration never grants elevated health permissions through roles. An approved,
-- unexpired, non-revoked request remains the only input accepted by
-- admin.account_has_elevated_access for an exact subject + capability.

begin;

alter table admin.elevated_access_requests
  add column if not exists requested_ttl_minutes integer,
  add column if not exists version integer not null default 1;

update admin.elevated_access_requests
set requested_ttl_minutes = greatest(
  5,
  least(
    case when capability='women_health.read.elevated' then 30 else 60 end,
    coalesce(ceil(extract(epoch from (expires_at_utc - reviewed_at_utc)) / 60.0)::integer, 15)
  )
)
where requested_ttl_minutes is null;

alter table admin.elevated_access_requests
  alter column requested_ttl_minutes set not null;

alter table admin.elevated_access_requests
  drop constraint if exists elevated_access_requests_requested_ttl_minutes_check;
alter table admin.elevated_access_requests
  add constraint elevated_access_requests_requested_ttl_minutes_check check (
    requested_ttl_minutes between 5 and 60
    and (capability <> 'women_health.read.elevated' or requested_ttl_minutes <= 30)
  );

alter table admin.elevated_access_requests
  drop constraint if exists elevated_access_requests_version_check;
alter table admin.elevated_access_requests
  add constraint elevated_access_requests_version_check check (version >= 1);

create unique index if not exists uq_admin_break_glass_pending
  on admin.elevated_access_requests(requester_account_id, subject_person_id, capability)
  where status='Pending';

create or replace function admin.create_break_glass_request(
  p_actor_account_id uuid,
  p_subject_person_id uuid,
  p_capability character varying,
  p_ttl_minutes integer,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path = admin, core, identity, pg_temp
as $$
declare
  v_operation constant character varying(120) := 'security.break_glass.request';
  v_existing admin.idempotency_keys%rowtype;
  v_request_id uuid;
  v_response jsonb;
  v_max_ttl integer;
begin
  if not admin.account_has_permission(p_actor_account_id, 'security.break_glass.request') then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,v_operation,'break_glass_request',null,'Denied',
      'Break-glass request permission is not granted.',p_correlation_id,
      p_idempotency_key,true,jsonb_build_object('code','permission_denied')
    );
    return jsonb_build_object('httpStatus',403,'code','permission_denied','replayed',false);
  end if;

  if p_capability not in ('health.read.elevated','women_health.read.elevated') then
    return jsonb_build_object('httpStatus',400,'code','break_glass_capability_invalid','replayed',false);
  end if;
  v_max_ttl := case when p_capability='women_health.read.elevated' then 30 else 60 end;
  if p_ttl_minutes is null or p_ttl_minutes < 5 or p_ttl_minutes > v_max_ttl then
    return jsonb_build_object('httpStatus',400,'code','break_glass_ttl_invalid','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','break_glass_reason_invalid','replayed',false);
  end if;
  if not exists(select 1 from core.persons where id=p_subject_person_id) then
    return jsonb_build_object('httpStatus',404,'code','break_glass_subject_not_found','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0
  ));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation
    and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','replayed',false);
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  if exists(
    select 1 from admin.elevated_access_requests
    where requester_account_id=p_actor_account_id and subject_person_id=p_subject_person_id
      and capability=p_capability and status='Pending'
  ) then
    v_response := jsonb_build_object(
      'httpStatus',409,'code','break_glass_pending_exists',
      'message','A matching break-glass request is already pending.','replayed',false
    );
  else
    insert into admin.elevated_access_requests(
      requester_account_id,subject_person_id,capability,reason,status,
      requested_ttl_minutes,requested_at_utc,version
    ) values (
      p_actor_account_id,p_subject_person_id,p_capability,trim(p_reason),'Pending',
      p_ttl_minutes,now(),1
    ) returning id into v_request_id;

    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,v_operation,'break_glass_request',v_request_id::text,'Succeeded',
      trim(p_reason),p_correlation_id,p_idempotency_key,true,
      jsonb_build_object(
        'subjectPersonId',p_subject_person_id,
        'capability',p_capability,
        'ttlMinutes',p_ttl_minutes,
        'status','Pending'
      )
    );
    v_response := jsonb_build_object(
      'httpStatus',201,'code','ok','requestId',v_request_id,'status','Pending',
      'version',1,'replayed',false
    );
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,v_operation,'break_glass_request',null,'Denied',
      coalesce(v_response->>'message','Break-glass request denied.'),p_correlation_id,
      p_idempotency_key,true,jsonb_build_object('code',v_response->>'code')
    );
  end if;

  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,
      response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation
    and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function admin.mutate_break_glass_request(
  p_actor_account_id uuid,
  p_request_id uuid,
  p_action character varying,
  p_expected_version integer,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path = admin, identity, pg_temp
as $$
declare
  v_action character varying(16) := lower(trim(coalesce(p_action,'')));
  v_operation character varying(120);
  v_existing admin.idempotency_keys%rowtype;
  v_request admin.elevated_access_requests%rowtype;
  v_response jsonb;
  v_status character varying(24);
  v_expires timestamp with time zone;
begin
  if v_action not in ('approve','deny','revoke') then
    return jsonb_build_object('httpStatus',400,'code','break_glass_action_invalid','replayed',false);
  end if;
  v_operation := 'security.break_glass.' || v_action;

  if v_action in ('approve','deny') then
    if not admin.account_has_permission(p_actor_account_id,'security.break_glass.approve') then
      return jsonb_build_object('httpStatus',403,'code','permission_denied','replayed',false);
    end if;
  elsif not (
    admin.account_has_permission(p_actor_account_id,'security.break_glass.approve')
    or admin.account_has_permission(p_actor_account_id,'security.break_glass.request')
  ) then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','replayed',false);
  end if;

  if p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object('httpStatus',400,'code','break_glass_version_invalid','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','break_glass_reason_invalid','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0
  ));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation
    and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  perform pg_advisory_xact_lock(hashtextextended('break_glass:' || p_request_id::text,0));
  select * into v_request from admin.elevated_access_requests where id=p_request_id for update;

  if v_request.id is null then
    v_response := jsonb_build_object('httpStatus',404,'code','break_glass_not_found','replayed',false);
  elsif v_request.version <> p_expected_version then
    v_response := jsonb_build_object(
      'httpStatus',409,'code','break_glass_version_conflict','version',v_request.version,'replayed',false
    );
  elsif v_action in ('approve','deny') and v_request.requester_account_id=p_actor_account_id then
    v_response := jsonb_build_object(
      'httpStatus',403,'code','break_glass_self_approval_denied',
      'message','A requester cannot approve or deny their own break-glass request.','replayed',false
    );
  elsif v_action in ('approve','deny') and v_request.status <> 'Pending' then
    v_response := jsonb_build_object('httpStatus',409,'code','break_glass_not_pending','replayed',false);
  elsif v_action='revoke' and v_request.status <> 'Approved' then
    v_response := jsonb_build_object('httpStatus',409,'code','break_glass_not_active','replayed',false);
  elsif v_action='revoke'
    and v_request.requester_account_id <> p_actor_account_id
    and not admin.account_has_permission(p_actor_account_id,'security.break_glass.approve') then
    v_response := jsonb_build_object('httpStatus',403,'code','break_glass_revoke_denied','replayed',false);
  else
    if v_action='approve' then
      v_status := 'Approved';
      v_expires := now() + make_interval(mins => v_request.requested_ttl_minutes);
      update admin.elevated_access_requests
      set status=v_status,reviewed_by_account_id=p_actor_account_id,reviewed_at_utc=now(),
          review_reason=trim(p_reason),expires_at_utc=v_expires,version=version+1
      where id=p_request_id;
    elsif v_action='deny' then
      v_status := 'Denied';
      update admin.elevated_access_requests
      set status=v_status,reviewed_by_account_id=p_actor_account_id,reviewed_at_utc=now(),
          review_reason=trim(p_reason),expires_at_utc=null,version=version+1
      where id=p_request_id;
    else
      v_status := 'Revoked';
      update admin.elevated_access_requests
      set status=v_status,revoked_at_utc=now(),review_reason=trim(p_reason),version=version+1
      where id=p_request_id;
    end if;

    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,v_operation,'break_glass_request',p_request_id::text,'Succeeded',
      trim(p_reason),p_correlation_id,p_idempotency_key,true,
      jsonb_build_object(
        'requesterAccountId',v_request.requester_account_id,
        'subjectPersonId',v_request.subject_person_id,
        'capability',v_request.capability,
        'status',v_status,
        'ttlMinutes',v_request.requested_ttl_minutes
      )
    );
    v_response := jsonb_build_object(
      'httpStatus',200,'code','ok','requestId',p_request_id,'action',v_action,
      'status',v_status,'version',v_request.version+1,'expiresAtUtc',v_expires,'replayed',false
    );
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,v_operation,'break_glass_request',p_request_id::text,'Denied',
      coalesce(v_response->>'message','Break-glass mutation denied.'),p_correlation_id,
      p_idempotency_key,true,jsonb_build_object('code',v_response->>'code')
    );
  end if;

  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,
      response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation
    and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function admin.create_break_glass_request(
  uuid,uuid,character varying,integer,character varying,uuid,character varying,character varying
) from public;
revoke all on function admin.mutate_break_glass_request(
  uuid,uuid,character varying,integer,character varying,uuid,character varying,character varying
) from public;

grant execute on function admin.create_break_glass_request(
  uuid,uuid,character varying,integer,character varying,uuid,character varying,character varying
) to lifemate_admin_runtime;
grant execute on function admin.mutate_break_glass_request(
  uuid,uuid,character varying,integer,character varying,uuid,character varying,character varying
) to lifemate_admin_runtime;

grant select on admin.elevated_access_requests to lifemate_admin_runtime;

commit;
