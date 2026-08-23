-- Canonical, narrowly scoped Command Center staff mutations.
--
-- The browser never calls these tables directly. These routines are invoked only
-- by lifemate-admin-api after Auth/AAL2 validation. They intentionally preserve
-- the separation between administrative workforce membership and consumer data.

begin;

create or replace function admin.mutate_staff_membership(
  p_actor_account_id uuid,
  p_target_account_id uuid,
  p_action character varying,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path = admin, identity, pg_temp
as $$
declare
  v_operation character varying(120);
  v_action character varying(24) := lower(trim(coalesce(p_action,'')));
  v_existing admin.idempotency_keys%rowtype;
  v_before_status character varying(24);
  v_after_status character varying(24);
  v_response jsonb;
  v_noop boolean := false;
begin
  v_operation := 'staff.membership.' || v_action;
  if not admin.account_has_permission(p_actor_account_id, 'security.staff.manage') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_target_account_id = p_actor_account_id then
    return jsonb_build_object('httpStatus',403,'code','staff_self_mutation_denied','message','Staff members cannot mutate their own membership.','replayed',false);
  end if;
  if v_action not in ('activate','disable','reenable') then
    return jsonb_build_object('httpStatus',400,'code','staff_action_invalid','message','Staff membership action is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','staff_action_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key, 0));
  select * into v_existing from admin.idempotency_keys
    where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
    values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  perform pg_advisory_xact_lock(hashtextextended('staff.member:' || p_target_account_id::text, 0));
  if not exists (select 1 from identity.accounts where id=p_target_account_id) then
    v_response := jsonb_build_object('httpStatus',404,'code','staff_account_not_found','message','Target account was not found.','replayed',false);
  elsif exists (
    select 1 from admin.member_roles mr join admin.roles r on r.id=mr.role_id
    where mr.account_id=p_target_account_id and r.code='founder' and mr.revoked_at_utc is null
  ) then
    v_response := jsonb_build_object('httpStatus',403,'code','founder_role_immutable','message','Founder membership cannot be changed through the ordinary staff workflow.','replayed',false);
  else
    select status into v_before_status from admin.members where account_id=p_target_account_id for update;
    if v_action='activate' then
      if v_before_status is null then
        insert into admin.members(account_id,status,created_by_account_id)
          values(p_target_account_id,'Active',p_actor_account_id);
        v_after_status := 'Active';
      elsif v_before_status='Active' then
        v_after_status := 'Active'; v_noop := true;
      else
        v_response := jsonb_build_object('httpStatus',409,'code','staff_membership_not_activatable','message','Use reenable for a disabled membership.','replayed',false);
      end if;
    elsif v_action='disable' then
      if v_before_status is null then
        v_response := jsonb_build_object('httpStatus',404,'code','staff_membership_not_found','message','Target staff membership was not found.','replayed',false);
      elsif v_before_status='Disabled' then
        v_after_status := 'Disabled'; v_noop := true;
      elsif v_before_status='Revoked' then
        v_response := jsonb_build_object('httpStatus',409,'code','staff_membership_revoked','message','A revoked staff membership cannot be changed.','replayed',false);
      else
        update admin.members set status='Disabled',disabled_at_utc=now(),updated_at_utc=now() where account_id=p_target_account_id;
        v_after_status := 'Disabled';
      end if;
    else
      if v_before_status is null then
        v_response := jsonb_build_object('httpStatus',404,'code','staff_membership_not_found','message','Target staff membership was not found.','replayed',false);
      elsif v_before_status='Active' then
        v_after_status := 'Active'; v_noop := true;
      elsif v_before_status='Revoked' then
        v_response := jsonb_build_object('httpStatus',409,'code','staff_membership_revoked','message','A revoked staff membership cannot be re-enabled.','replayed',false);
      else
        update admin.members set status='Active',disabled_at_utc=null,updated_at_utc=now() where account_id=p_target_account_id;
        v_after_status := 'Active';
      end if;
    end if;
    if v_response is null then
      insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
        values(p_actor_account_id,v_operation,'admin_member',p_target_account_id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
          jsonb_build_object('beforeStatus',v_before_status,'afterStatus',v_after_status,'noop',v_noop));
      v_response := jsonb_build_object('httpStatus',case when v_before_status is null then 201 else 200 end,'code','ok','accountId',p_target_account_id,'previousStatus',v_before_status,'status',v_after_status,'noop',v_noop,'replayed',false);
    end if;
  end if;
  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
      values(p_actor_account_id,v_operation,'admin_member',p_target_account_id::text,'Denied',coalesce(v_response->>'message','Staff membership mutation denied.'),p_correlation_id,p_idempotency_key,false,jsonb_build_object('code',v_response->>'code'));
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function admin.mutate_staff_role(
  p_actor_account_id uuid, p_target_account_id uuid, p_role_code character varying, p_action character varying,
  p_reason character varying, p_correlation_id uuid, p_idempotency_key character varying, p_request_hash character varying
) returns jsonb
language plpgsql
set search_path = admin, pg_temp
as $$
declare
  v_operation character varying(120);
  v_action character varying(24) := lower(trim(coalesce(p_action,'')));
  v_role_code character varying(64) := lower(trim(coalesce(p_role_code,'')));
  v_existing admin.idempotency_keys%rowtype;
  v_role admin.roles%rowtype;
  v_actor_rank smallint;
  v_existing_membership_id uuid;
  v_response jsonb;
  v_noop boolean := false;
begin
  v_operation := 'staff.role.' || v_action;
  if not admin.account_has_permission(p_actor_account_id, 'security.staff.manage') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_target_account_id=p_actor_account_id then return jsonb_build_object('httpStatus',403,'code','staff_self_mutation_denied','message','Staff members cannot mutate their own roles.','replayed',false); end if;
  if v_action not in ('assign','revoke') or v_role_code !~ '^[a-z][a-z0-9_]{1,63}$' then return jsonb_build_object('httpStatus',400,'code','staff_role_invalid','message','Staff role action or role code is invalid.','replayed',false); end if;
  if v_role_code in ('founder','super_admin') then return jsonb_build_object('httpStatus',403,'code','privileged_role_immutable','message','Privileged roles cannot be changed through the ordinary staff workflow.','replayed',false); end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then return jsonb_build_object('httpStatus',400,'code','staff_action_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180 or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false); end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key, 0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash <> p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json || jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');
  perform pg_advisory_xact_lock(hashtextextended('staff.member:' || p_target_account_id::text, 0));
  select * into v_role from admin.roles where code=v_role_code for update;
  select min(r.rank) into v_actor_rank from admin.member_roles mr join admin.roles r on r.id=mr.role_id
    where mr.account_id=p_actor_account_id and r.status='Active' and mr.revoked_at_utc is null and mr.starts_at_utc<=now() and (mr.expires_at_utc is null or mr.expires_at_utc>now());
  if not exists(select 1 from admin.members where account_id=p_target_account_id and status='Active') then
    v_response:=jsonb_build_object('httpStatus',409,'code','staff_membership_inactive','message','Target staff membership must be active before changing roles.','replayed',false);
  elsif v_role.id is null or v_role.status <> 'Active' then
    v_response:=jsonb_build_object('httpStatus',404,'code','staff_role_not_assignable','message','Target role is unavailable.','replayed',false);
  elsif v_actor_rank is null or v_role.rank <= v_actor_rank then
    v_response:=jsonb_build_object('httpStatus',403,'code','staff_role_authority_denied','message','The requested role is outside the actor authority.','replayed',false);
  elsif v_action='assign' then
    select id into v_existing_membership_id from admin.member_roles where account_id=p_target_account_id and role_id=v_role.id and revoked_at_utc is null for update;
    if v_existing_membership_id is null then
      insert into admin.member_roles(account_id,role_id,granted_by_account_id) values(p_target_account_id,v_role.id,p_actor_account_id);
    else v_noop:=true; end if;
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','accountId',p_target_account_id,'roleCode',v_role_code,'action',v_action,'noop',v_noop,'replayed',false);
  else
    select id into v_existing_membership_id from admin.member_roles where account_id=p_target_account_id and role_id=v_role.id and revoked_at_utc is null for update;
    if v_existing_membership_id is null then v_noop:=true; else update admin.member_roles set revoked_at_utc=now() where id=v_existing_membership_id; end if;
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','accountId',p_target_account_id,'roleCode',v_role_code,'action',v_action,'noop',v_noop,'replayed',false);
  end if;
  if (v_response->>'httpStatus')::integer < 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
      values(p_actor_account_id,v_operation,'admin_member_role',p_target_account_id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,jsonb_build_object('roleCode',v_role_code,'action',v_action,'noop',v_noop));
  else
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
      values(p_actor_account_id,v_operation,'admin_member_role',p_target_account_id::text,'Denied',coalesce(v_response->>'message','Staff role mutation denied.'),p_correlation_id,p_idempotency_key,false,jsonb_build_object('roleCode',v_role_code,'code',v_response->>'code'));
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now() where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function admin.mutate_staff_membership(uuid,uuid,character varying,character varying,uuid,character varying,character varying) from public;
revoke all on function admin.mutate_staff_role(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) from public;
grant execute on function admin.mutate_staff_membership(uuid,uuid,character varying,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.mutate_staff_role(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;

commit;
