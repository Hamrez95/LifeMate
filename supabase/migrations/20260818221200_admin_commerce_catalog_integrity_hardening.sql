begin;

-- Database-level invariants complement the advisory locks used by the Admin API.
-- They protect catalog history even from future privileged maintenance tooling.
create unique index if not exists uq_commerce_plans_product_code_ci
  on commerce.plans(product_id, lower(code));

create unique index if not exists uq_commerce_prices_dimension_effective_from
  on commerce.prices(
    plan_id,
    ((coalesce(country_code, ''))),
    currency,
    store_provider,
    billing_period_months,
    effective_from_utc
  );

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
        set effective_to_utc = case
          when effective_to_utc is null or effective_to_utc > p_effective_from_utc
            then p_effective_from_utc
          else effective_to_utc
        end
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

comment on function admin.schedule_commerce_price(uuid,uuid,character varying,character varying,character varying,smallint,bigint,timestamptz,character varying,uuid,character varying,character varying)
  is 'Audited append-only price versioning. Existing explicit end-times are never extended and historical amounts are never overwritten.';

commit;
