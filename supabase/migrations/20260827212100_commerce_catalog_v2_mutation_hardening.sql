begin;

-- Hardening follow-up for #560: avoid PL/pgSQL identifier ambiguity and make
-- policy/create-price guards fail closed before the workflows become callable.
create or replace function admin.create_commerce_catalog_offer(
 p_actor uuid,p_product uuid,p_code varchar,p_name varchar,p_duration smallint,p_status varchar,p_gift boolean,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare
 op constant varchar:='commerce.catalog.offer.create';
 r jsonb; pid uuid; oid uuid; ps varchar; v_code varchar:=lower(trim(p_code));
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 if v_code !~ '^[a-z0-9][a-z0-9._-]{1,63}$' or p_name is null or length(trim(p_name)) not between 2 and 120 or p_duration not between 1 and 120 or p_status not in ('Hidden','Published','Retired') or p_gift is null then
   return jsonb_build_object('httpStatus',400,'code','catalog_offer_invalid','message','Offer mutation is invalid.','replayed',false);
 end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.offer:'||p_product::text||':'||v_code,0));
 select lifecycle_status into ps from commerce.products where id=p_product for update;
 if not found then r:=jsonb_build_object('httpStatus',404,'code','catalog_product_not_found','message','Product was not found.','replayed',false);
 elsif ps='Retired' or (p_status='Published' and ps<>'Published') then r:=jsonb_build_object('httpStatus',409,'code','catalog_product_state_conflict','message','Offer cannot be published for this product state.','replayed',false);
 elsif exists(select 1 from commerce.offers o where o.product_id=p_product and lower(o.code)=v_code) then r:=jsonb_build_object('httpStatus',409,'code','catalog_offer_conflict','message','Offer code already exists for this product.','replayed',false);
 elsif exists(select 1 from commerce.plans p where p.product_id=p_product and lower(p.code)=v_code) then r:=jsonb_build_object('httpStatus',409,'code','catalog_plan_conflict','message','Compatibility plan code already exists for this product.','replayed',false);
 else
   insert into commerce.plans(product_id,code,display_name,status,created_at_utc,updated_at_utc) values(p_product,v_code,trim(p_name),case when p_status='Retired' then 'Retired' else 'Active' end,now(),now()) returning id into pid;
   insert into commerce.offers(product_id,plan_id,code,display_name,duration_months,status,gift_eligible) values(p_product,pid,v_code,trim(p_name),p_duration,p_status,p_gift) returning id into oid;
   r:=jsonb_build_object('httpStatus',201,'code','ok','offerId',oid,'productId',p_product,'planId',pid,'status',p_status,'version',1,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.offer.create','commerce_offer',coalesce(oid::text,v_code),p_reason,p_correlation,jsonb_build_object('productId',p_product));
end $$;

create or replace function admin.schedule_commerce_offer_price(
 p_actor uuid,p_offer uuid,p_country varchar,p_currency varchar,p_provider varchar,p_amount bigint,p_effective timestamptz,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare
 op constant varchar:='commerce.catalog.offer.price.schedule';
 r jsonb; v commerce.offers%rowtype; price_id uuid;
 v_country varchar:=nullif(upper(trim(coalesce(p_country,''))),'');
 v_currency varchar:=upper(trim(coalesce(p_currency,'')));
 v_provider varchar:=lower(trim(coalesce(p_provider,'')));
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 if v_currency !~ '^[A-Z]{3}$' or (v_country is not null and v_country !~ '^[A-Z]{2}$') or v_provider !~ '^[a-z0-9][a-z0-9._:-]{1,39}$' or p_amount is null or p_amount<0 or p_effective is null or p_effective<now()-interval '5 minutes' then
   return jsonb_build_object('httpStatus',400,'code','catalog_offer_price_invalid','message','Offer price is invalid.','replayed',false);
 end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 select * into v from commerce.offers where id=p_offer for update;
 if not found then r:=jsonb_build_object('httpStatus',404,'code','catalog_offer_not_found','message','Offer was not found.','replayed',false);
 elsif v.status='Retired' or v.plan_id is null then r:=jsonb_build_object('httpStatus',409,'code','catalog_offer_not_sellable','message','Offer is not sellable.','replayed',false);
 else
   insert into commerce.prices(plan_id,offer_id,country_code,currency,store_provider,billing_period_months,amount_minor,status,effective_from_utc) values(v.plan_id,p_offer,v_country,v_currency,v_provider,v.duration_months,p_amount,'Active',p_effective) returning id into price_id;
   r:=jsonb_build_object('httpStatus',201,'code','ok','priceId',price_id,'offerId',p_offer,'effectiveFromUtc',p_effective,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.offer.price.schedule','commerce_price',coalesce(price_id::text,p_offer::text),p_reason,p_correlation,jsonb_build_object('offerId',p_offer,'currency',v_currency,'provider',v_provider));
end $$;

create or replace function admin.upsert_commerce_catalog_policy(
 p_actor uuid,p_product uuid,p_policy varchar,p_value jsonb,p_type varchar,p_status varchar,p_expected_version bigint,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare
 op constant varchar:='commerce.catalog.policy.upsert';
 r jsonb; v commerce.catalog_policies%rowtype; new_version bigint; v_exists boolean:=false;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 if p_policy !~ '^[a-z0-9][a-z0-9._-]{1,127}$' or p_type not in ('integer','boolean','string','json') or p_status not in ('Active','Retired') or p_value is null then
   return jsonb_build_object('httpStatus',400,'code','catalog_policy_invalid','message','Catalog policy mutation is invalid.','replayed',false);
 end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.policy:'||p_product::text||':'||p_policy,0));
 select * into v from commerce.catalog_policies where product_id=p_product and policy_key=p_policy for update;
 v_exists:=found;
 if not exists(select 1 from commerce.products where id=p_product and lifecycle_status<>'Retired') then r:=jsonb_build_object('httpStatus',409,'code','catalog_product_state_conflict','message','Policy requires an active catalog product.','replayed',false);
 elsif v_exists and p_expected_version is null then r:=jsonb_build_object('httpStatus',409,'code','catalog_policy_exists','message','Expected version is required to update an existing policy.','currentVersion',v.version,'replayed',false);
 elsif v_exists and v.version<>p_expected_version then r:=jsonb_build_object('httpStatus',409,'code','catalog_version_conflict','message','Policy changed; refresh before updating.','currentVersion',v.version,'replayed',false);
 elsif not v_exists and p_expected_version is not null then r:=jsonb_build_object('httpStatus',409,'code','catalog_policy_missing','message','Policy does not exist at the expected version.','replayed',false);
 else
   if v_exists then update commerce.catalog_policies set value_json=p_value,value_type=p_type,status=p_status,version=version+1,updated_at_utc=now() where product_id=p_product and policy_key=p_policy returning version into new_version;
   else insert into commerce.catalog_policies(product_id,policy_key,value_json,value_type,status,version) values(p_product,p_policy,p_value,p_type,p_status,1) returning version into new_version; end if;
   r:=jsonb_build_object('httpStatus',200,'code','ok','productId',p_product,'policyKey',p_policy,'status',p_status,'version',new_version,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.policy.upsert','commerce_catalog_policy',p_product::text||':'||p_policy,p_reason,p_correlation,jsonb_build_object('valueType',p_type));
end $$;

create or replace function admin.create_commerce_catalog_bundle(
 p_actor uuid,p_code varchar,p_name varchar,p_status varchar,p_gift boolean,p_offers uuid[],p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare
 op constant varchar:='commerce.catalog.bundle.create';
 r jsonb; bid uuid; v_code varchar:=lower(trim(p_code)); expected_count int:=coalesce(array_length(p_offers,1),0); valid_count int;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then return jsonb_build_object('httpStatus',400,'code','catalog_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false); end if;
 if v_code !~ '^[a-z0-9][a-z0-9._-]{1,63}$' or p_name is null or length(trim(p_name)) not between 2 and 120 or p_status not in ('Hidden','Published','Retired') or p_gift is null or expected_count not between 1 and 32 or coalesce(array_length(array(select distinct x from unnest(p_offers) x),1),0)<>expected_count then
   return jsonb_build_object('httpStatus',400,'code','catalog_bundle_invalid','message','Bundle mutation is invalid.','replayed',false);
 end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.bundle:'||v_code,0));
 select count(*) into valid_count from commerce.offers o where o.id=any(p_offers) and o.status<>'Retired' and (p_status<>'Published' or o.status='Published');
 if valid_count<>expected_count then r:=jsonb_build_object('httpStatus',409,'code','catalog_bundle_items_invalid','message','Bundle contains missing, retired, or unpublished offers.','replayed',false);
 elsif exists(select 1 from commerce.bundles b where lower(b.code)=v_code) then r:=jsonb_build_object('httpStatus',409,'code','catalog_bundle_conflict','message','Bundle code already exists.','replayed',false);
 else
   insert into commerce.bundles(code,display_name,status,gift_eligible) values(v_code,trim(p_name),p_status,p_gift) returning id into bid;
   insert into commerce.bundle_items(bundle_id,offer_id,quantity) select bid,x,1 from unnest(p_offers) x;
   r:=jsonb_build_object('httpStatus',201,'code','ok','bundleId',bid,'status',p_status,'version',1,'itemCount',expected_count,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.bundle.create','commerce_bundle',coalesce(bid::text,v_code),p_reason,p_correlation,jsonb_build_object('offerIds',p_offers));
end $$;

commit;
