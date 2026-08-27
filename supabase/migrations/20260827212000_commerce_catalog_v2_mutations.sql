begin;

-- #560 Canonical Product / Offer / Bundle / Policy mutation boundary.
-- Extends #486 and preserves legacy Plan compatibility without destructive rewrites.
alter table commerce.products add column if not exists version bigint not null default 1 check (version >= 1);

create or replace function admin.commerce_catalog_v2_replay(
  p_actor uuid,p_operation varchar,p_key varchar,p_hash varchar
) returns jsonb language plpgsql set search_path=admin,pg_temp as $$
declare v admin.idempotency_keys%rowtype;
begin
  if p_key is null or length(p_key) not between 8 and 180 or p_hash is null or length(p_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text||':'||p_operation||':'||p_key,0));
  select * into v from admin.idempotency_keys where actor_account_id=p_actor and operation=p_operation and idempotency_key=p_key for update;
  if found then
    if v.request_hash<>p_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false); end if;
    if v.status='Completed' and v.response_json is not null then return v.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor,p_operation,p_key,p_hash,'Processing');
  return null;
end $$;

create or replace function admin.commerce_catalog_v2_finish(
  p_actor uuid,p_operation varchar,p_key varchar,p_response jsonb,p_action varchar,
  p_resource_type varchar,p_resource_id varchar,p_reason varchar,p_correlation uuid,p_metadata jsonb
) returns jsonb language plpgsql set search_path=admin,pg_temp as $$
begin
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor,p_action,p_resource_type,p_resource_id,case when (p_response->>'httpStatus')::int<400 then 'Succeeded' else 'Denied' end,
    coalesce(nullif(trim(p_reason),''),p_response->>'message'),p_correlation,p_key,false,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('code',p_response->>'code'));
  update admin.idempotency_keys set status='Completed',response_status=(p_response->>'httpStatus')::int,response_json=p_response,updated_at_utc=now()
  where actor_account_id=p_actor and operation=p_operation and idempotency_key=p_key;
  return p_response;
end $$;

revoke all on function admin.commerce_catalog_v2_replay(uuid,varchar,varchar,varchar) from public,anon,authenticated;
revoke all on function admin.commerce_catalog_v2_finish(uuid,varchar,varchar,jsonb,varchar,varchar,varchar,varchar,uuid,jsonb) from public,anon,authenticated;

create or replace function admin.update_commerce_catalog_product(
 p_actor uuid,p_product uuid,p_name varchar,p_status varchar,p_expected_version bigint,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.product.update'; r jsonb; v commerce.products%rowtype; before jsonb;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.product:'||p_product::text,0));
 select * into v from commerce.products where id=p_product for update;
 if not found then r:=jsonb_build_object('httpStatus',404,'code','catalog_product_not_found','message','Product was not found.','replayed',false);
 elsif p_expected_version is null or v.version<>p_expected_version then r:=jsonb_build_object('httpStatus',409,'code','catalog_version_conflict','message','Product changed; refresh before updating.','currentVersion',v.version,'replayed',false);
 elsif p_status not in ('Hidden','Published','Retired') or p_name is null or length(trim(p_name)) not between 2 and 120 then r:=jsonb_build_object('httpStatus',400,'code','catalog_product_invalid','message','Product mutation is invalid.','replayed',false);
 else
   before:=jsonb_build_object('name',v.display_name,'status',v.lifecycle_status,'version',v.version);
   update commerce.products set display_name=trim(p_name),lifecycle_status=p_status,status=case when p_status='Retired' then 'Retired' else 'Active' end,version=version+1,updated_at_utc=now() where id=p_product returning * into v;
   if p_status='Retired' then update commerce.offers set status='Retired',version=version+1,updated_at_utc=now() where product_id=p_product and status<>'Retired'; end if;
   r:=jsonb_build_object('httpStatus',200,'code','ok','productId',v.id,'status',v.lifecycle_status,'version',v.version,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.product.update','commerce_product',p_product::text,p_reason,p_correlation,jsonb_build_object('before',before));
end $$;

create or replace function admin.create_commerce_catalog_offer(
 p_actor uuid,p_product uuid,p_code varchar,p_name varchar,p_duration smallint,p_status varchar,p_gift boolean,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.offer.create'; r jsonb; pid uuid; oid uuid; ps varchar; code varchar:=lower(trim(p_code));
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.offer:'||p_product::text||':'||code,0));
 select lifecycle_status into ps from commerce.products where id=p_product for update;
 if not found then r:=jsonb_build_object('httpStatus',404,'code','catalog_product_not_found','message','Product was not found.','replayed',false);
 elsif ps='Retired' or (p_status='Published' and ps<>'Published') then r:=jsonb_build_object('httpStatus',409,'code','catalog_product_state_conflict','message','Offer cannot be published for this product state.','replayed',false);
 elsif exists(select 1 from commerce.offers where product_id=p_product and lower(code)=code) then r:=jsonb_build_object('httpStatus',409,'code','catalog_offer_conflict','message','Offer code already exists for this product.','replayed',false);
 else
   insert into commerce.plans(product_id,code,display_name,status,created_at_utc,updated_at_utc) values(p_product,code,trim(p_name),case when p_status='Retired' then 'Retired' else 'Active' end,now(),now()) returning id into pid;
   insert into commerce.offers(product_id,plan_id,code,display_name,duration_months,status,gift_eligible) values(p_product,pid,code,trim(p_name),p_duration,p_status,p_gift) returning id into oid;
   r:=jsonb_build_object('httpStatus',201,'code','ok','offerId',oid,'productId',p_product,'planId',pid,'status',p_status,'version',1,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.offer.create','commerce_offer',coalesce(oid::text,code),p_reason,p_correlation,jsonb_build_object('productId',p_product));
end $$;

create or replace function admin.update_commerce_catalog_offer(
 p_actor uuid,p_offer uuid,p_name varchar,p_duration smallint,p_status varchar,p_gift boolean,p_expected_version bigint,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.offer.update'; r jsonb; v commerce.offers%rowtype; ps varchar; before jsonb;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 select * into v from commerce.offers where id=p_offer for update;
 if not found then r:=jsonb_build_object('httpStatus',404,'code','catalog_offer_not_found','message','Offer was not found.','replayed',false);
 elsif v.version<>p_expected_version then r:=jsonb_build_object('httpStatus',409,'code','catalog_version_conflict','message','Offer changed; refresh before updating.','currentVersion',v.version,'replayed',false);
 else
   select lifecycle_status into ps from commerce.products where id=v.product_id;
   if p_status='Published' and ps<>'Published' then r:=jsonb_build_object('httpStatus',409,'code','catalog_product_state_conflict','message','Offer cannot be published for this product state.','replayed',false);
   else
     before:=jsonb_build_object('name',v.display_name,'durationMonths',v.duration_months,'status',v.status,'giftEligible',v.gift_eligible,'version',v.version);
     update commerce.offers set display_name=trim(p_name),duration_months=p_duration,status=p_status,gift_eligible=p_gift,version=version+1,updated_at_utc=now() where id=p_offer returning * into v;
     if v.plan_id is not null then update commerce.plans set display_name=v.display_name,status=case when p_status='Retired' then 'Retired' else 'Active' end,updated_at_utc=now() where id=v.plan_id; end if;
     r:=jsonb_build_object('httpStatus',200,'code','ok','offerId',v.id,'status',v.status,'version',v.version,'replayed',false);
   end if;
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.offer.update','commerce_offer',p_offer::text,p_reason,p_correlation,jsonb_build_object('before',before));
end $$;

create or replace function admin.schedule_commerce_offer_price(
 p_actor uuid,p_offer uuid,p_country varchar,p_currency varchar,p_provider varchar,p_amount bigint,p_effective timestamptz,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.offer.price.schedule'; r jsonb; v commerce.offers%rowtype; price_id uuid; country varchar:=nullif(upper(trim(coalesce(p_country,''))),''); currency varchar:=upper(trim(p_currency)); provider varchar:=lower(trim(p_provider));
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 select * into v from commerce.offers where id=p_offer for update;
 if not found then r:=jsonb_build_object('httpStatus',404,'code','catalog_offer_not_found','message','Offer was not found.','replayed',false);
 elsif v.status='Retired' or v.plan_id is null then r:=jsonb_build_object('httpStatus',409,'code','catalog_offer_not_sellable','message','Offer is not sellable.','replayed',false);
 elsif currency !~ '^[A-Z]{3}$' or (country is not null and country !~ '^[A-Z]{2}$') or provider !~ '^[a-z0-9][a-z0-9._:-]{1,39}$' or p_amount<0 or p_effective<now()-interval '5 minutes' then r:=jsonb_build_object('httpStatus',400,'code','catalog_offer_price_invalid','message','Offer price is invalid.','replayed',false);
 else
   insert into commerce.prices(plan_id,offer_id,country_code,currency,store_provider,billing_period_months,amount_minor,status,effective_from_utc) values(v.plan_id,p_offer,country,currency,provider,v.duration_months,p_amount,'Active',p_effective) returning id into price_id;
   r:=jsonb_build_object('httpStatus',201,'code','ok','priceId',price_id,'offerId',p_offer,'effectiveFromUtc',p_effective,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.offer.price.schedule','commerce_price',coalesce(price_id::text,p_offer::text),p_reason,p_correlation,jsonb_build_object('offerId',p_offer,'currency',currency,'provider',provider));
end $$;

create or replace function admin.upsert_commerce_catalog_policy(
 p_actor uuid,p_product uuid,p_policy varchar,p_value jsonb,p_type varchar,p_status varchar,p_expected_version bigint,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.policy.upsert'; r jsonb; v commerce.catalog_policies%rowtype; new_version bigint;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.policy:'||p_product::text||':'||p_policy,0));
 select * into v from commerce.catalog_policies where product_id=p_product and policy_key=p_policy for update;
 if not exists(select 1 from commerce.products where id=p_product and lifecycle_status<>'Retired') then r:=jsonb_build_object('httpStatus',409,'code','catalog_product_state_conflict','message','Policy requires an active catalog product.','replayed',false);
 elsif found and p_expected_version is null then r:=jsonb_build_object('httpStatus',409,'code','catalog_policy_exists','message','Expected version is required to update an existing policy.','currentVersion',v.version,'replayed',false);
 elsif found and v.version<>p_expected_version then r:=jsonb_build_object('httpStatus',409,'code','catalog_version_conflict','message','Policy changed; refresh before updating.','currentVersion',v.version,'replayed',false);
 elsif not found and p_expected_version is not null then r:=jsonb_build_object('httpStatus',409,'code','catalog_policy_missing','message','Policy does not exist at the expected version.','replayed',false);
 else
   if found then update commerce.catalog_policies set value_json=p_value,value_type=p_type,status=p_status,version=version+1,updated_at_utc=now() where product_id=p_product and policy_key=p_policy returning version into new_version;
   else insert into commerce.catalog_policies(product_id,policy_key,value_json,value_type,status,version) values(p_product,p_policy,p_value,p_type,p_status,1) returning version into new_version; end if;
   r:=jsonb_build_object('httpStatus',200,'code','ok','productId',p_product,'policyKey',p_policy,'status',p_status,'version',new_version,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.policy.upsert','commerce_catalog_policy',p_product::text||':'||p_policy,p_reason,p_correlation,jsonb_build_object('valueType',p_type));
end $$;

create or replace function admin.create_commerce_catalog_bundle(
 p_actor uuid,p_code varchar,p_name varchar,p_status varchar,p_gift boolean,p_offers uuid[],p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.bundle.create'; r jsonb; bid uuid; code varchar:=lower(trim(p_code)); expected_count int:=coalesce(array_length(p_offers,1),0); valid_count int;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.bundle:'||code,0));
 select count(*) into valid_count from commerce.offers where id=any(p_offers) and status<>'Retired' and (p_status<>'Published' or status='Published');
 if expected_count<1 or expected_count>32 or valid_count<>expected_count then r:=jsonb_build_object('httpStatus',409,'code','catalog_bundle_items_invalid','message','Bundle contains missing, retired, or unpublished offers.','replayed',false);
 elsif exists(select 1 from commerce.bundles where lower(code)=code) then r:=jsonb_build_object('httpStatus',409,'code','catalog_bundle_conflict','message','Bundle code already exists.','replayed',false);
 else
   insert into commerce.bundles(code,display_name,status,gift_eligible) values(code,trim(p_name),p_status,p_gift) returning id into bid;
   insert into commerce.bundle_items(bundle_id,offer_id,quantity) select bid,x,1 from unnest(p_offers) x;
   r:=jsonb_build_object('httpStatus',201,'code','ok','bundleId',bid,'status',p_status,'version',1,'itemCount',expected_count,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.bundle.create','commerce_bundle',coalesce(bid::text,code),p_reason,p_correlation,jsonb_build_object('offerIds',p_offers));
end $$;

create or replace function admin.update_commerce_catalog_bundle(
 p_actor uuid,p_bundle uuid,p_name varchar,p_status varchar,p_gift boolean,p_offers uuid[],p_expected_version bigint,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.bundle.update'; r jsonb; v commerce.bundles%rowtype; expected_count int:=coalesce(array_length(p_offers,1),0); valid_count int; before jsonb;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 select * into v from commerce.bundles where id=p_bundle for update;
 if not found then r:=jsonb_build_object('httpStatus',404,'code','catalog_bundle_not_found','message','Bundle was not found.','replayed',false);
 elsif v.version<>p_expected_version then r:=jsonb_build_object('httpStatus',409,'code','catalog_version_conflict','message','Bundle changed; refresh before updating.','currentVersion',v.version,'replayed',false);
 else
   select count(*) into valid_count from commerce.offers where id=any(p_offers) and status<>'Retired' and (p_status<>'Published' or status='Published');
   if expected_count<1 or expected_count>32 or valid_count<>expected_count then r:=jsonb_build_object('httpStatus',409,'code','catalog_bundle_items_invalid','message','Bundle contains missing, retired, or unpublished offers.','replayed',false);
   else
     before:=jsonb_build_object('name',v.display_name,'status',v.status,'giftEligible',v.gift_eligible,'version',v.version);
     update commerce.bundles set display_name=trim(p_name),status=p_status,gift_eligible=p_gift,version=version+1,updated_at_utc=now() where id=p_bundle returning * into v;
     delete from commerce.bundle_items where bundle_id=p_bundle;
     insert into commerce.bundle_items(bundle_id,offer_id,quantity) select p_bundle,x,1 from unnest(p_offers) x;
     r:=jsonb_build_object('httpStatus',200,'code','ok','bundleId',v.id,'status',v.status,'version',v.version,'itemCount',expected_count,'replayed',false);
   end if;
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.bundle.update','commerce_bundle',p_bundle::text,p_reason,p_correlation,jsonb_build_object('before',before,'offerIds',p_offers));
end $$;

revoke all on function admin.update_commerce_catalog_product(uuid,uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function admin.create_commerce_catalog_offer(uuid,uuid,varchar,varchar,smallint,varchar,boolean,varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function admin.update_commerce_catalog_offer(uuid,uuid,varchar,smallint,varchar,boolean,bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function admin.schedule_commerce_offer_price(uuid,uuid,varchar,varchar,varchar,bigint,timestamptz,varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function admin.upsert_commerce_catalog_policy(uuid,uuid,varchar,jsonb,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function admin.create_commerce_catalog_bundle(uuid,varchar,varchar,varchar,boolean,uuid[],varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function admin.update_commerce_catalog_bundle(uuid,uuid,varchar,varchar,boolean,uuid[],bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated;

grant execute on function admin.update_commerce_catalog_product(uuid,uuid,varchar,varchar,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.create_commerce_catalog_offer(uuid,uuid,varchar,varchar,smallint,varchar,boolean,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.update_commerce_catalog_offer(uuid,uuid,varchar,smallint,varchar,boolean,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.schedule_commerce_offer_price(uuid,uuid,varchar,varchar,varchar,bigint,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.upsert_commerce_catalog_policy(uuid,uuid,varchar,jsonb,varchar,varchar,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.create_commerce_catalog_bundle(uuid,varchar,varchar,varchar,boolean,uuid[],varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.update_commerce_catalog_bundle(uuid,uuid,varchar,varchar,boolean,uuid[],bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

commit;
