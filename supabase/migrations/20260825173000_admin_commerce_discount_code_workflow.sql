begin;

-- Independent discount-code issuance is a separate high-risk Commerce capability.
-- Codes remain attached to an existing Promotion; this workflow never reprices or
-- migrates subscriptions and never grants a commercial entitlement by itself.
alter table commerce.discount_codes
  add column if not exists version integer not null default 1 check (version > 0);

insert into admin.permissions(code, domain, risk_level, role_assignable, description) values
('commerce.discount_code.write','commerce','HIGH_RISK',true,'Issue and change lifecycle of bounded promotion discount codes through the audited server workflow')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id, permission_code)
select r.id, 'commerce.discount_code.write'
from admin.roles r
where r.code in ('founder','super_admin','product')
on conflict do nothing;

create or replace function admin.issue_commerce_discount_codes(
  p_actor_account_id uuid,
  p_promotion_id uuid,
  p_explicit_codes character varying[],
  p_generate_count smallint,
  p_prefix character varying,
  p_max_redemptions integer,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, commerce, pg_temp
as $$
declare
  v_operation constant character varying := 'commerce.discount_code.issue';
  v_existing admin.idempotency_keys%rowtype;
  v_promotion commerce.promotions%rowtype;
  v_response jsonb;
  v_codes character varying[] := '{}';
  v_raw character varying;
  v_code character varying(64);
  v_prefix character varying(24) := upper(trim(coalesce(p_prefix, '')));
  v_count integer := 0;
  v_attempt integer;
  v_row commerce.discount_codes%rowtype;
  v_items jsonb := '[]'::jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'commerce.discount_code.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','discount_code_request_invalid','message','Discount-code request metadata is invalid.','replayed',false);
  end if;
  if p_max_redemptions is not null and (p_max_redemptions < 1 or p_max_redemptions > 10000000) then
    return jsonb_build_object('httpStatus',400,'code','discount_code_limit_invalid','message','Discount-code redemption limit is invalid.','replayed',false);
  end if;
  if coalesce(array_length(p_explicit_codes,1),0) > 0 and coalesce(p_generate_count,0) > 0 then
    return jsonb_build_object('httpStatus',400,'code','discount_code_mode_invalid','message','Choose explicit codes or generated codes, not both.','replayed',false);
  end if;

  if coalesce(array_length(p_explicit_codes,1),0) > 0 then
    if array_length(p_explicit_codes,1) > 50 then
      return jsonb_build_object('httpStatus',400,'code','discount_code_batch_too_large','message','At most 50 discount codes may be issued per request.','replayed',false);
    end if;
    foreach v_raw in array p_explicit_codes loop
      v_code := upper(trim(v_raw));
      if v_code is null or v_code !~ '^[A-Z0-9][A-Z0-9._-]{2,63}$' then
        return jsonb_build_object('httpStatus',400,'code','discount_code_invalid','message','One or more discount codes are invalid.','replayed',false);
      end if;
      if v_code = any(v_codes) then
        return jsonb_build_object('httpStatus',400,'code','discount_code_duplicate','message','The request contains a duplicate discount code.','replayed',false);
      end if;
      v_codes := array_append(v_codes, v_code);
    end loop;
  else
    if p_generate_count is null or p_generate_count not between 1 and 50 then
      return jsonb_build_object('httpStatus',400,'code','discount_code_batch_invalid','message','Generated discount-code count must be between 1 and 50.','replayed',false);
    end if;
    if v_prefix <> '' and (length(v_prefix) > 20 or v_prefix !~ '^[A-Z0-9][A-Z0-9._-]{0,19}$') then
      return jsonb_build_object('httpStatus',400,'code','discount_code_prefix_invalid','message','Discount-code prefix is invalid.','replayed',false);
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key, 0));
  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key
  for update;
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

  perform pg_advisory_xact_lock(hashtextextended('commerce.promotion:' || p_promotion_id::text, 0));
  select * into v_promotion from commerce.promotions where id=p_promotion_id for update;
  if not found then
    v_response := jsonb_build_object('httpStatus',404,'code','commerce_promotion_not_found','message','Commerce promotion was not found.','replayed',false);
  elsif v_promotion.status = 'Expired' or (v_promotion.ends_at_utc is not null and v_promotion.ends_at_utc <= now()) then
    v_response := jsonb_build_object('httpStatus',409,'code','commerce_promotion_expired','message','Discount codes cannot be issued for an expired promotion.','replayed',false);
  elsif v_promotion.max_redemptions is not null and p_max_redemptions is not null and p_max_redemptions > v_promotion.max_redemptions then
    v_response := jsonb_build_object('httpStatus',400,'code','discount_code_limit_invalid','message','Discount-code limit cannot exceed the promotion limit.','replayed',false);
  else
    if coalesce(array_length(v_codes,1),0) = 0 then
      while v_count < p_generate_count loop
        v_attempt := 0;
        loop
          v_attempt := v_attempt + 1;
          v_code := case when v_prefix = '' then '' else v_prefix || '-' end || upper(substr(encode(gen_random_bytes(10),'hex'),1,12));
          exit when not exists(select 1 from commerce.discount_codes where lower(code)=lower(v_code));
          if v_attempt >= 8 then
            raise exception 'Unable to allocate unique discount code';
          end if;
        end loop;
        v_codes := array_append(v_codes, v_code);
        v_count := v_count + 1;
      end loop;
    end if;

    foreach v_code in array v_codes loop
      perform pg_advisory_xact_lock(hashtextextended('commerce.discount_code:' || lower(v_code), 0));
      if exists(select 1 from commerce.discount_codes where lower(code)=lower(v_code)) then
        v_response := jsonb_build_object('httpStatus',409,'code','discount_code_conflict','message','One or more discount codes already exist.','replayed',false);
        exit;
      end if;
    end loop;

    if v_response is null then
      foreach v_code in array v_codes loop
        insert into commerce.discount_codes(promotion_id,code,status,max_redemptions,version)
        values(p_promotion_id,v_code,'Active',p_max_redemptions,1)
        returning * into v_row;
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'codeId',v_row.id,
          'code',v_row.code,
          'status',v_row.status,
          'maxRedemptions',v_row.max_redemptions,
          'version',v_row.version
        ));
      end loop;
      v_response := jsonb_build_object(
        'httpStatus',201,
        'code','ok',
        'promotionId',p_promotion_id,
        'issuedCount',coalesce(array_length(v_codes,1),0),
        'items',v_items,
        'replayed',false
      );
    end if;
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(
    p_actor_account_id,
    v_operation,
    'commerce_promotion',
    p_promotion_id::text,
    case when (v_response->>'httpStatus')::integer < 400 then 'Succeeded' else 'Denied' end,
    trim(p_reason),
    p_correlation_id,
    p_idempotency_key,
    false,
    jsonb_build_object(
      'code',v_response->>'code',
      'issuedCount',case when (v_response->>'httpStatus')::integer < 400 then coalesce(array_length(v_codes,1),0) else 0 end,
      'generated',coalesce(p_generate_count,0) > 0,
      'maxRedemptions',p_max_redemptions
    )
  );
  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function admin.set_commerce_discount_code_status(
  p_actor_account_id uuid,
  p_promotion_id uuid,
  p_code_id uuid,
  p_status character varying,
  p_expected_version integer,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, commerce, pg_temp
as $$
declare
  v_operation constant character varying := 'commerce.discount_code.status';
  v_existing admin.idempotency_keys%rowtype;
  v_code commerce.discount_codes%rowtype;
  v_previous character varying;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'commerce.discount_code.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_status not in ('Active','Disabled') or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object('httpStatus',400,'code','discount_code_status_invalid','message','Discount-code lifecycle fields are invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','discount_code_request_invalid','message','Discount-code request metadata is invalid.','replayed',false);
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

  perform pg_advisory_xact_lock(hashtextextended('commerce.discount_code_id:' || p_code_id::text, 0));
  select * into v_code from commerce.discount_codes
  where id=p_code_id and promotion_id=p_promotion_id for update;
  if not found then
    v_response := jsonb_build_object('httpStatus',404,'code','discount_code_not_found','message','Discount code was not found.','replayed',false);
  elsif v_code.version <> p_expected_version then
    v_response := jsonb_build_object('httpStatus',409,'code','discount_code_version_conflict','message','Discount-code version does not match.','replayed',false);
  else
    v_previous := v_code.status;
    if v_previous = p_status then
      v_response := jsonb_build_object('httpStatus',200,'code','ok','promotionId',p_promotion_id,'codeId',p_code_id,'previousStatus',v_previous,'status',v_previous,'version',v_code.version,'noop',true,'replayed',false);
    else
      update commerce.discount_codes
      set status=p_status,version=version+1,updated_at_utc=now()
      where id=p_code_id
      returning * into v_code;
      v_response := jsonb_build_object('httpStatus',200,'code','ok','promotionId',p_promotion_id,'codeId',p_code_id,'previousStatus',v_previous,'status',v_code.status,'version',v_code.version,'noop',false,'replayed',false);
    end if;
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(
    p_actor_account_id,
    v_operation,
    'commerce_discount_code',
    p_code_id::text,
    case when (v_response->>'httpStatus')::integer < 400 then 'Succeeded' else 'Denied' end,
    trim(p_reason),
    p_correlation_id,
    p_idempotency_key,
    false,
    jsonb_build_object('code',v_response->>'code','promotionId',p_promotion_id,'targetStatus',p_status,'expectedVersion',p_expected_version)
  );
  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function admin.issue_commerce_discount_codes(uuid,uuid,character varying[],smallint,character varying,integer,character varying,uuid,character varying,character varying) from public;
grant execute on function admin.issue_commerce_discount_codes(uuid,uuid,character varying[],smallint,character varying,integer,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
revoke all on function admin.set_commerce_discount_code_status(uuid,uuid,uuid,character varying,integer,character varying,uuid,character varying,character varying) from public;
grant execute on function admin.set_commerce_discount_code_status(uuid,uuid,uuid,character varying,integer,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;

commit;
