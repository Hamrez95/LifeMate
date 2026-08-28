begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('platform.update_policy.write','platform','HIGH_RISK',true,'Create or update server-managed product minimum-version and update policies')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,'platform.update_policy.write'
from admin.roles r
where r.code in ('founder','super_admin','product','technical')
on conflict do nothing;

create or replace function platform.upsert_product_update_policy_admin(
  p_actor_account_id uuid,
  p_product varchar,
  p_platform varchar,
  p_minimum_supported_version varchar,
  p_recommended_version varchar,
  p_mode varchar,
  p_reason_code varchar,
  p_message_key varchar,
  p_status varchar,
  p_effective_at_utc timestamptz,
  p_expected_version bigint,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=platform,admin,pg_temp
as $$
declare
  v_operation constant varchar := 'platform.product_update_policy.upsert';
  v_existing_idempotency admin.idempotency_keys%rowtype;
  v_current platform.product_update_policies%rowtype;
  v_policy platform.product_update_policies%rowtype;
  v_response jsonb;
  v_http integer;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_expected_version is null or p_expected_version<0 then
    return jsonb_build_object('httpStatus',400,'code','expected_version_invalid','message','expectedVersion must be zero or greater.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing_idempotency from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key
  for update;
  if found then
    if v_existing_idempotency.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different update-policy mutation.','replayed',false);
    end if;
    if v_existing_idempotency.status='Completed' and v_existing_idempotency.response_json is not null then
      return v_existing_idempotency.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching update-policy mutation is still processing.','replayed',false);
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  if not admin.account_has_permission(p_actor_account_id,'platform.update_policy.write') then
    v_response:=jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  elsif p_product not in ('wellmate','caremate') then
    v_response:=jsonb_build_object('httpStatus',400,'code','product_invalid','message','Product is invalid.','replayed',false);
  elsif p_platform not in ('android','ios','web','windows','macos','linux') then
    v_response:=jsonb_build_object('httpStatus',400,'code','platform_invalid','message','Platform is invalid.','replayed',false);
  elsif p_minimum_supported_version is null or p_minimum_supported_version !~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$'
     or (p_recommended_version is not null and p_recommended_version !~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$') then
    v_response:=jsonb_build_object('httpStatus',400,'code','version_invalid','message','Version value is invalid.','replayed',false);
  elsif p_mode not in ('Soft','Force') or p_reason_code not in ('Routine','Critical','Security','BreakingCompatibility')
     or (p_mode='Force' and p_reason_code not in ('Critical','Security','BreakingCompatibility')) then
    v_response:=jsonb_build_object('httpStatus',400,'code','update_mode_invalid','message','Update mode or reason code is invalid.','replayed',false);
  elsif p_status not in ('Active','Disabled') then
    v_response:=jsonb_build_object('httpStatus',400,'code','status_invalid','message','Policy status is invalid.','replayed',false);
  elsif p_message_key is not null and p_message_key !~ '^[a-z][a-z0-9._-]{2,95}$' then
    v_response:=jsonb_build_object('httpStatus',400,'code','message_key_invalid','message','Message key is invalid.','replayed',false);
  elsif p_effective_at_utc is null then
    v_response:=jsonb_build_object('httpStatus',400,'code','effective_at_invalid','message','effectiveAtUtc is required.','replayed',false);
  end if;

  if v_response is null then
    select * into v_current from platform.product_update_policies
    where product=p_product and platform=p_platform for update;

    if found and v_current.version<>p_expected_version then
      v_response:=jsonb_build_object('httpStatus',409,'code','version_conflict','message','Product update policy changed since it was loaded.','currentVersion',v_current.version,'replayed',false);
    elsif not found and p_expected_version<>0 then
      v_response:=jsonb_build_object('httpStatus',409,'code','version_conflict','message','Product update policy does not exist at the expected version.','currentVersion',0,'replayed',false);
    else
      if found then
        update platform.product_update_policies set
          minimum_supported_version=p_minimum_supported_version,
          recommended_version=p_recommended_version,
          mode=p_mode,
          reason_code=p_reason_code,
          message_key=p_message_key,
          status=p_status,
          effective_at_utc=p_effective_at_utc,
          updated_by_account_id=p_actor_account_id
        where product=p_product and platform=p_platform
        returning * into v_policy;
      else
        insert into platform.product_update_policies(
          product,platform,minimum_supported_version,recommended_version,mode,reason_code,
          message_key,status,version,effective_at_utc,updated_at_utc,updated_by_account_id
        ) values (
          p_product,p_platform,p_minimum_supported_version,p_recommended_version,p_mode,p_reason_code,
          p_message_key,p_status,1,p_effective_at_utc,now(),p_actor_account_id
        ) returning * into v_policy;
      end if;

      insert into admin.audit_events(
        actor_account_id,action,resource_type,resource_id,result,reason,
        correlation_id,request_id,elevated_access,metadata_json
      ) values (
        p_actor_account_id,'platform.product_update_policy.upsert','product_update_policy',
        p_product||':'||p_platform,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
        jsonb_build_object(
          'product',p_product,'platform',p_platform,'policyVersion',v_policy.version,
          'mode',v_policy.mode,'reasonCode',v_policy.reason_code,'status',v_policy.status,
          'effectiveAtUtc',v_policy.effective_at_utc
        )
      );

      v_response:=jsonb_build_object(
        'httpStatus',200,'code','ok','replayed',false,
        'policy',jsonb_build_object(
          'product',v_policy.product,
          'platform',v_policy.platform,
          'minimumSupportedVersion',v_policy.minimum_supported_version,
          'recommendedVersion',v_policy.recommended_version,
          'mode',v_policy.mode,
          'reasonCode',v_policy.reason_code,
          'messageKey',v_policy.message_key,
          'status',v_policy.status,
          'policyVersion',v_policy.version,
          'effectiveAtUtc',v_policy.effective_at_utc,
          'updatedAtUtc',v_policy.updated_at_utc
        )
      );
    end if;
  end if;

  if (v_response->>'httpStatus')::integer>=400 then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,'platform.product_update_policy.upsert','product_update_policy',
      coalesce(p_product,'unknown')||':'||coalesce(p_platform,'unknown'),'Denied',
      coalesce(v_response->>'code','mutation_denied'),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('product',p_product,'platform',p_platform,'expectedVersion',p_expected_version)
    );
  end if;

  v_http:=coalesce((v_response->>'httpStatus')::integer,500);
  update admin.idempotency_keys set
    status='Completed',response_status=v_http,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function platform.upsert_product_update_policy_admin(uuid,varchar,varchar,varchar,varchar,varchar,varchar,varchar,varchar,timestamptz,bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated;

do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function platform.upsert_product_update_policy_admin(uuid,varchar,varchar,varchar,varchar,varchar,varchar,varchar,varchar,timestamptz,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
  end if;
end $$;

commit;
