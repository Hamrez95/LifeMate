begin;

alter table admin.roles
  add column if not exists version bigint not null default 1,
  add column if not exists created_by_account_id uuid,
  add column if not exists updated_by_account_id uuid,
  add column if not exists retired_at_utc timestamptz;

alter table admin.roles drop constraint if exists ck_admin_roles_version_positive;
alter table admin.roles add constraint ck_admin_roles_version_positive check (version >= 1);

create or replace function admin.mutate_custom_role(
  p_actor_account_id uuid,
  p_action character varying,
  p_role_code character varying,
  p_display_name character varying,
  p_rank smallint,
  p_expected_version bigint,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path = admin, pg_temp
as $$
declare
  v_action character varying(24) := lower(trim(coalesce(p_action,'')));
  v_role_code character varying(64) := lower(trim(coalesce(p_role_code,'')));
  v_operation character varying(128);
  v_existing admin.idempotency_keys%rowtype;
  v_role admin.roles%rowtype;
  v_actor_rank smallint;
  v_response jsonb;
  v_before jsonb;
begin
  v_operation := 'security.custom_role.' || v_action;

  if not admin.account_has_permission(p_actor_account_id,'security.roles.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if v_action not in ('create','update','retire') then
    return jsonb_build_object('httpStatus',400,'code','custom_role_action_invalid','message','Custom role action is invalid.','replayed',false);
  end if;
  if v_role_code !~ '^[a-z][a-z0-9_]{1,63}$' or v_role_code in ('founder','super_admin') then
    return jsonb_build_object('httpStatus',400,'code','custom_role_code_invalid','message','Custom role code is invalid or reserved.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','custom_role_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  select min(r.rank) into v_actor_rank
  from admin.member_roles mr
  join admin.roles r on r.id=mr.role_id
  where mr.account_id=p_actor_account_id
    and r.status='Active'
    and mr.revoked_at_utc is null
    and mr.starts_at_utc<=now()
    and (mr.expires_at_utc is null or mr.expires_at_utc>now());
  if v_actor_rank is null then
    return jsonb_build_object('httpStatus',403,'code','custom_role_authority_denied','message','Actor role authority is unavailable.','replayed',false);
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

  perform pg_advisory_xact_lock(hashtextextended('admin.custom_role:' || v_role_code,0));
  select * into v_role from admin.roles where code=v_role_code for update;

  if v_action='create' then
    if v_role.id is not null then
      v_response:=jsonb_build_object('httpStatus',409,'code','custom_role_exists','message','A role with this code already exists.','replayed',false);
    elsif p_display_name is null or length(trim(p_display_name))<2 or length(trim(p_display_name))>120 then
      v_response:=jsonb_build_object('httpStatus',400,'code','custom_role_name_invalid','message','Display name must contain between 2 and 120 characters.','replayed',false);
    elsif p_rank is null or p_rank<1 or p_rank>1000 or p_rank<=v_actor_rank then
      v_response:=jsonb_build_object('httpStatus',403,'code','custom_role_rank_denied','message','Custom role rank must be below the actor authority.','replayed',false);
    else
      insert into admin.roles(code,display_name,rank,status,is_system,version,created_by_account_id,updated_by_account_id)
      values(v_role_code,trim(p_display_name),p_rank,'Active',false,1,p_actor_account_id,p_actor_account_id)
      returning * into v_role;
      v_response:=jsonb_build_object('httpStatus',201,'code','ok','roleCode',v_role.code,'displayName',v_role.display_name,'rank',v_role.rank,'status',v_role.status,'version',v_role.version,'replayed',false);
    end if;
  elsif v_role.id is null then
    v_response:=jsonb_build_object('httpStatus',404,'code','custom_role_not_found','message','Custom role was not found.','replayed',false);
  elsif v_role.is_system then
    v_response:=jsonb_build_object('httpStatus',403,'code','system_role_immutable','message','System roles cannot be changed through the custom-role workflow.','replayed',false);
  elsif v_role.rank<=v_actor_rank then
    v_response:=jsonb_build_object('httpStatus',403,'code','custom_role_authority_denied','message','The custom role is outside the actor authority.','replayed',false);
  elsif p_expected_version is null or p_expected_version<>v_role.version then
    v_response:=jsonb_build_object('httpStatus',409,'code','custom_role_version_conflict','message','Custom role changed; refresh before updating.','currentVersion',v_role.version,'replayed',false);
  else
    v_before:=jsonb_build_object('displayName',v_role.display_name,'rank',v_role.rank,'status',v_role.status,'version',v_role.version);
    if v_action='update' then
      if p_display_name is null or length(trim(p_display_name))<2 or length(trim(p_display_name))>120 then
        v_response:=jsonb_build_object('httpStatus',400,'code','custom_role_name_invalid','message','Display name must contain between 2 and 120 characters.','replayed',false);
      elsif p_rank is null or p_rank<1 or p_rank>1000 or p_rank<=v_actor_rank then
        v_response:=jsonb_build_object('httpStatus',403,'code','custom_role_rank_denied','message','Custom role rank must be below the actor authority.','replayed',false);
      else
        update admin.roles set display_name=trim(p_display_name),rank=p_rank,version=version+1,updated_by_account_id=p_actor_account_id,updated_at_utc=now()
        where id=v_role.id returning * into v_role;
        v_response:=jsonb_build_object('httpStatus',200,'code','ok','roleCode',v_role.code,'displayName',v_role.display_name,'rank',v_role.rank,'status',v_role.status,'version',v_role.version,'replayed',false);
      end if;
    else
      if v_role.status='Disabled' then
        v_response:=jsonb_build_object('httpStatus',200,'code','ok','roleCode',v_role.code,'displayName',v_role.display_name,'rank',v_role.rank,'status',v_role.status,'version',v_role.version,'noop',true,'replayed',false);
      else
        update admin.roles set status='Disabled',retired_at_utc=now(),version=version+1,updated_by_account_id=p_actor_account_id,updated_at_utc=now()
        where id=v_role.id returning * into v_role;
        v_response:=jsonb_build_object('httpStatus',200,'code','ok','roleCode',v_role.code,'displayName',v_role.display_name,'rank',v_role.rank,'status',v_role.status,'version',v_role.version,'noop',false,'replayed',false);
      end if;
    end if;
  end if;

  if (v_response->>'httpStatus')::integer < 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,v_operation,'admin_role',v_role_code,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('before',v_before,'after',jsonb_build_object('displayName',v_response->>'displayName','rank',v_response->>'rank','status',v_response->>'status','version',v_response->>'version')));
  else
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,v_operation,'admin_role',v_role_code,'Denied',coalesce(v_response->>'message','Custom role mutation denied.'),p_correlation_id,p_idempotency_key,false,jsonb_build_object('code',v_response->>'code'));
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function admin.mutate_custom_role_permission(
  p_actor_account_id uuid,
  p_role_code character varying,
  p_permission_code character varying,
  p_action character varying,
  p_expected_version bigint,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path = admin, pg_temp
as $$
declare
  v_role_code character varying(64):=lower(trim(coalesce(p_role_code,'')));
  v_permission_code character varying(120):=lower(trim(coalesce(p_permission_code,'')));
  v_action character varying(16):=lower(trim(coalesce(p_action,'')));
  v_operation character varying(160);
  v_existing admin.idempotency_keys%rowtype;
  v_role admin.roles%rowtype;
  v_permission admin.permissions%rowtype;
  v_actor_rank smallint;
  v_changed boolean:=false;
  v_row_count integer:=0;
  v_response jsonb;
begin
  v_operation:='security.custom_role.permission.' || v_action;
  if not admin.account_has_permission(p_actor_account_id,'security.roles.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if v_action not in ('assign','revoke') then
    return jsonb_build_object('httpStatus',400,'code','custom_role_permission_action_invalid','message','Permission action is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','custom_role_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  select min(r.rank) into v_actor_rank from admin.member_roles mr join admin.roles r on r.id=mr.role_id
  where mr.account_id=p_actor_account_id and r.status='Active' and mr.revoked_at_utc is null and mr.starts_at_utc<=now() and (mr.expires_at_utc is null or mr.expires_at_utc>now());

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json || jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  perform pg_advisory_xact_lock(hashtextextended('admin.custom_role:' || v_role_code,0));
  select * into v_role from admin.roles where code=v_role_code for update;
  select * into v_permission from admin.permissions where code=v_permission_code;

  if v_role.id is null then
    v_response:=jsonb_build_object('httpStatus',404,'code','custom_role_not_found','message','Custom role was not found.','replayed',false);
  elsif v_role.is_system then
    v_response:=jsonb_build_object('httpStatus',403,'code','system_role_immutable','message','System role permissions cannot be changed through the custom-role workflow.','replayed',false);
  elsif v_role.status<>'Active' then
    v_response:=jsonb_build_object('httpStatus',409,'code','custom_role_inactive','message','Custom role must be active before changing permissions.','replayed',false);
  elsif v_actor_rank is null or v_role.rank<=v_actor_rank then
    v_response:=jsonb_build_object('httpStatus',403,'code','custom_role_authority_denied','message','The custom role is outside the actor authority.','replayed',false);
  elsif p_expected_version is null or p_expected_version<>v_role.version then
    v_response:=jsonb_build_object('httpStatus',409,'code','custom_role_version_conflict','message','Custom role changed; refresh before updating.','currentVersion',v_role.version,'replayed',false);
  elsif v_permission.code is null then
    v_response:=jsonb_build_object('httpStatus',404,'code','permission_not_found','message','Permission was not found.','replayed',false);
  elsif v_action='assign' and (not v_permission.role_assignable or v_permission.risk_level='ELEVATED') then
    v_response:=jsonb_build_object('httpStatus',403,'code','permission_not_role_assignable','message','This permission cannot be assigned through roles.','replayed',false);
  elsif v_action='assign' and not admin.account_has_permission(p_actor_account_id,v_permission.code) then
    v_response:=jsonb_build_object('httpStatus',403,'code','permission_delegation_denied','message','Actor cannot delegate a permission they do not hold.','replayed',false);
  else
    if v_action='assign' then
      insert into admin.role_permissions(role_id,permission_code) values(v_role.id,v_permission.code) on conflict do nothing;
      get diagnostics v_row_count = row_count;
    else
      delete from admin.role_permissions where role_id=v_role.id and permission_code=v_permission.code;
      get diagnostics v_row_count = row_count;
    end if;
    v_changed:=v_row_count>0;
    if v_changed then
      update admin.roles set version=version+1,updated_by_account_id=p_actor_account_id,updated_at_utc=now() where id=v_role.id returning * into v_role;
    end if;
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','roleCode',v_role.code,'permissionCode',v_permission.code,'action',v_action,'version',v_role.version,'noop',not v_changed,'replayed',false);
  end if;

  if (v_response->>'httpStatus')::integer < 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,v_operation,'admin_role_permission',v_role_code,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('permissionCode',v_permission_code,'action',v_action,'version',v_response->>'version','noop',v_response->>'noop'));
  else
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,v_operation,'admin_role_permission',v_role_code,'Denied',coalesce(v_response->>'message','Custom role permission mutation denied.'),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('permissionCode',v_permission_code,'code',v_response->>'code'));
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function admin.mutate_custom_role(uuid,character varying,character varying,character varying,smallint,bigint,character varying,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function admin.mutate_custom_role_permission(uuid,character varying,character varying,character varying,bigint,character varying,uuid,character varying,character varying) from public,anon,authenticated;
grant execute on function admin.mutate_custom_role(uuid,character varying,character varying,character varying,smallint,bigint,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.mutate_custom_role_permission(uuid,character varying,character varying,character varying,bigint,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;

comment on column admin.roles.version is 'Optimistic concurrency version for role policy changes.';
comment on column admin.roles.created_by_account_id is 'Audit provenance UUID only; deliberately no identity FK so lifecycle operations are not blocked.';
comment on column admin.roles.updated_by_account_id is 'Audit provenance UUID only; deliberately no identity FK so lifecycle operations are not blocked.';

commit;
