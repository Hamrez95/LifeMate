begin;

-- Admin-owned commercial catalog mutations. These workflows intentionally keep
-- the browser away from direct Commerce writes and preserve price history by
-- appending versions instead of overwriting financial records.

alter table commerce.plans
  add column if not exists updated_at_utc timestamptz not null default now();

insert into admin.permissions(code, domain, risk_level, role_assignable, description) values
('commerce.plan.write','commerce','HIGH_RISK',true,'Create, rename, activate or retire sellable Commerce plans through an audited workflow'),
('commerce.price.write','commerce','HIGH_RISK',true,'Append versioned Commerce prices through an audited workflow; historical amounts are never overwritten')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id, permission_code)
select r.id, p.code
from admin.roles r
join admin.permissions p on p.code in ('commerce.plan.write','commerce.price.write')
where r.code in ('founder','super_admin')
on conflict do nothing;

insert into admin.role_permissions(role_id, permission_code)
select r.id, 'commerce.plan.write'
from admin.roles r
where r.code='product'
on conflict do nothing;

insert into admin.role_permissions(role_id, permission_code)
select r.id, 'commerce.price.write'
from admin.roles r
where r.code='finance'
on conflict do nothing;

create or replace function admin.create_commerce_plan(
  p_actor_account_id uuid,
  p_product_id uuid,
  p_code character varying,
  p_display_name character varying,
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
  v_operation constant character varying := 'commerce.plan.create';
  v_existing admin.idempotency_keys%rowtype;
  v_code character varying(64) := lower(trim(p_code));
  v_plan_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'commerce.plan.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_product_id is null then
    return jsonb_build_object('httpStatus',400,'code','plan_product_invalid','message','Product is required.','replayed',false);
  end if;
  if v_code is null or v_code !~ '^[a-z0-9][a-z0-9._-]{1,63}$' then
    return jsonb_build_object('httpStatus',400,'code','plan_code_invalid','message','Plan code is invalid.','replayed',false);
  end if;
  if p_display_name is null or length(trim(p_display_name)) < 2 or length(trim(p_display_name)) > 120 then
    return jsonb_build_object('httpStatus',400,'code','plan_name_invalid','message','Plan display name is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','plan_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || p_idempotency_key, 0));
  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id=p_actor_account_id
    and operation=v_operation
    and idempotency_key=p_idempotency_key
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

  perform pg_advisory_xact_lock(hashtextextended('commerce.plan:' || p_product_id::text || ':' || v_code, 0));

  if not exists(select 1 from commerce.products where id=p_product_id and status='Active') then
    v_response := jsonb_build_object('httpStatus',409,'code','commerce_product_inactive','message','Plan can only be created for an active product.','replayed',false);
  elsif exists(select 1 from commerce.plans where product_id=p_product_id and lower(code)=v_code) then
    v_response := jsonb_build_object('httpStatus',409,'code','commerce_plan_conflict','message','Plan code already exists for this product.','replayed',false);
  else
    insert into commerce.plans(product_id,code,display_name,status,created_at_utc,updated_at_utc)
    values(p_product_id,v_code,trim(p_display_name),'Active',now(),now())
    returning id into v_plan_id;

    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,'commerce.plan.create','commerce_plan',v_plan_id::text,'Succeeded',trim(p_reason),
      p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('productId',p_product_id,'planCode',v_code,'status','Active')
    );
    v_response := jsonb_build_object('httpStatus',201,'code','ok','planId',v_plan_id,'status','Active','replayed',false);
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,'commerce.plan.create','commerce_plan',null,'Denied',coalesce(v_response->>'message','Plan creation denied'),
      p_correlation_id,p_idempotency_key,false,jsonb_build_object('code',v_response->>'code','productId',p_product_id)
    );
  end if;

  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.update_commerce_plan(
  p_actor_account_id uuid,
  p_plan_id uuid,
  p_display_name character varying,
  p_target_status character varying,
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
  v_operation constant character varying := 'commerce.plan.update';
  v_existing admin.idempotency_keys%rowtype;
  v_previous_status character varying(24);
  v_product_id uuid;
  v_code character varying(64);
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'commerce.plan.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_display_name is null or length(trim(p_display_name)) < 2 or length(trim(p_display_name)) > 120 then
    return jsonb_build_object('httpStatus',400,'code','plan_name_invalid','message','Plan display name is invalid.','replayed',false);
  end if;
  if p_target_status not in ('Active','Retired') then
    return jsonb_build_object('httpStatus',400,'code','plan_status_invalid','message','Plan status is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','plan_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || p_idempotency_key, 0));
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

  select status,product_id,code into v_previous_status,v_product_id,v_code
  from commerce.plans where id=p_plan_id for update;

  if not found then
    v_response := jsonb_build_object('httpStatus',404,'code','commerce_plan_not_found','message','Commerce plan was not found.','replayed',false);
  elsif p_target_status='Active' and not exists(select 1 from commerce.products where id=v_product_id and status='Active') then
    v_response := jsonb_build_object('httpStatus',409,'code','commerce_product_inactive','message','A plan cannot be activated while its product is retired.','replayed',false);
  else
    update commerce.plans
    set display_name=trim(p_display_name),status=p_target_status,updated_at_utc=now()
    where id=p_plan_id;

    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,'commerce.plan.update','commerce_plan',p_plan_id::text,'Succeeded',trim(p_reason),
      p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('planCode',v_code,'previousStatus',v_previous_status,'status',p_target_status)
    );
    v_response := jsonb_build_object('httpStatus',200,'code','ok','planId',p_plan_id,'previousStatus',v_previous_status,'status',p_target_status,'replayed',false);
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,'commerce.plan.update','commerce_plan',p_plan_id::text,'Denied',coalesce(v_response->>'message','Plan update denied'),
      p_correlation_id,p_idempotency_key,false,jsonb_build_object('code',v_response->>'code')
    );
  end if;
  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.schedule_commerce_price(
  p_actor_account_id uuid,
  p_plan_id uuid,
  p_country_code character varying,
  p_currency character varying,
  p_store_provider character varying,
  p_billing_period_months smallint,
  p_amount_minor bigint,
  p_effective_from_utc timestamptz,
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
  v_operation constant character varying := 'commerce.price.schedule';
  v_existing admin.idempotency_keys%rowtype;
  v_country character varying(2) := nullif(upper(trim(coalesce(p_country_code,''))), '');
  v_currency character varying(3) := upper(trim(p_currency));
  v_provider character varying(40) := lower(trim(p_store_provider));
  v_latest_id uuid;
  v_latest_from timestamptz;
  v_price_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'commerce.price.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if v_country is not null and v_country !~ '^[A-Z]{2}$' then
    return jsonb_build_object('httpStatus',400,'code','price_country_invalid','message','Country code is invalid.','replayed',false);
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    return jsonb_build_object('httpStatus',400,'code','price_currency_invalid','message','Currency is invalid.','replayed',false);
  end if;
  if v_provider is null or v_provider !~ '^[a-z0-9][a-z0-9._:-]{1,39}$' then
    return jsonb_build_object('httpStatus',400,'code','price_provider_invalid','message','Store provider is invalid.','replayed',false);
  end if;
  if p_billing_period_months is null or p_billing_period_months < 1 or p_billing_period_months > 120 then
    return jsonb_build_object('httpStatus',400,'code','price_period_invalid','message','Billing period is invalid.','replayed',false);
  end if;
  if p_amount_minor is null or p_amount_minor < 0 then
    return jsonb_build_object('httpStatus',400,'code','price_amount_invalid','message','Price amount is invalid.','replayed',false);
  end if;
  if p_effective_from_utc is null or p_effective_from_utc < now() - interval '5 minutes' then
    return jsonb_build_object('httpStatus',400,'code','price_effective_time_invalid','message','Price effective time cannot be backdated.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','price_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || p_idempotency_key, 0));
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

  perform pg_advisory_xact_lock(hashtextextended(
    'commerce.price:' || p_plan_id::text || ':' || coalesce(v_country,'*') || ':' || v_currency || ':' || v_provider || ':' || p_billing_period_months::text,
    0
  ));

  if not exists(
    select 1 from commerce.plans pl
    join commerce.products p on p.id=pl.product_id
    where pl.id=p_plan_id and pl.status='Active' and p.status='Active'
  ) then
    v_response := jsonb_build_object('httpStatus',409,'code','commerce_plan_inactive','message','Price can only be scheduled for an active plan on an active product.','replayed',false);
  else
    select id,effective_from_utc into v_latest_id,v_latest_from
    from commerce.prices
    where plan_id=p_plan_id
      and country_code is not distinct from v_country
      and currency=v_currency
      and store_provider=v_provider
      and billing_period_months=p_billing_period_months
    order by effective_from_utc desc,id desc
    limit 1
    for update;

    if v_latest_from is not null and p_effective_from_utc <= v_latest_from then
      v_response := jsonb_build_object('httpStatus',409,'code','price_version_not_append_only','message','New price versions must start after the latest existing version.','replayed',false);
    else
      if v_latest_id is not null then
        update commerce.prices
        set effective_to_utc=p_effective_from_utc
        where id=v_latest_id;
      end if;

      insert into commerce.prices(
        plan_id,country_code,currency,store_provider,billing_period_months,amount_minor,status,effective_from_utc,effective_to_utc
      ) values (
        p_plan_id,v_country,v_currency,v_provider,p_billing_period_months,p_amount_minor,'Active',p_effective_from_utc,null
      ) returning id into v_price_id;

      insert into admin.audit_events(
        actor_account_id,action,resource_type,resource_id,result,reason,
        correlation_id,request_id,elevated_access,metadata_json
      ) values (
        p_actor_account_id,'commerce.price.schedule','commerce_price',v_price_id::text,'Succeeded',trim(p_reason),
        p_correlation_id,p_idempotency_key,false,
        jsonb_build_object(
          'planId',p_plan_id,'countryCode',v_country,'currency',v_currency,'storeProvider',v_provider,
          'billingPeriodMonths',p_billing_period_months,'amountMinor',p_amount_minor::text,'effectiveFromUtc',p_effective_from_utc
        )
      );
      v_response := jsonb_build_object('httpStatus',201,'code','ok','priceId',v_price_id,'planId',p_plan_id,'effectiveFromUtc',p_effective_from_utc,'replayed',false);
    end if;
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,'commerce.price.schedule','commerce_price',null,'Denied',coalesce(v_response->>'message','Price scheduling denied'),
      p_correlation_id,p_idempotency_key,false,jsonb_build_object('code',v_response->>'code','planId',p_plan_id)
    );
  end if;
  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

revoke all on function admin.create_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) from public;
revoke all on function admin.update_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) from public;
revoke all on function admin.schedule_commerce_price(uuid,uuid,character varying,character varying,character varying,smallint,bigint,timestamptz,character varying,uuid,character varying,character varying) from public;

do $$
begin
  if to_regrole('anon') is not null then
    revoke all on function admin.create_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) from anon;
    revoke all on function admin.update_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) from anon;
    revoke all on function admin.schedule_commerce_price(uuid,uuid,character varying,character varying,character varying,smallint,bigint,timestamptz,character varying,uuid,character varying,character varying) from anon;
  end if;
  if to_regrole('authenticated') is not null then
    revoke all on function admin.create_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) from authenticated;
    revoke all on function admin.update_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) from authenticated;
    revoke all on function admin.schedule_commerce_price(uuid,uuid,character varying,character varying,character varying,smallint,bigint,timestamptz,character varying,uuid,character varying,character varying) from authenticated;
  end if;
end
$$;

grant execute on function admin.create_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.update_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.schedule_commerce_price(uuid,uuid,character varying,character varying,character varying,smallint,bigint,timestamptz,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;

comment on function admin.create_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying)
  is 'Audited, idempotent creation of a sellable Commerce plan. Product/code are immutable after creation.';
comment on function admin.update_commerce_plan(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying)
  is 'Audited Plan display-name/lifecycle update. Retiring a plan never mutates existing subscriptions.';
comment on function admin.schedule_commerce_price(uuid,uuid,character varying,character varying,character varying,smallint,bigint,timestamptz,character varying,uuid,character varying,character varying)
  is 'Audited append-only price versioning. Historical amount records are never overwritten.';

commit;
