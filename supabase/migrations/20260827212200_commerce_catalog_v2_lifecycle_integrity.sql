begin;

-- Retiring a Product or Offer must not leave a Published bundle selling a
-- retired dependency. Bundles are retired, never deleted, preserving history.
create or replace function admin.update_commerce_catalog_product(
 p_actor uuid,p_product uuid,p_name varchar,p_status varchar,p_expected_version bigint,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.product.update'; r jsonb; v commerce.products%rowtype; before jsonb;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 or p_name is null or length(trim(p_name)) not between 2 and 120 or p_status not in ('Hidden','Published','Retired') then return jsonb_build_object('httpStatus',400,'code','catalog_product_invalid','message','Product mutation is invalid.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.product:'||p_product::text,0));
 select * into v from commerce.products where id=p_product for update;
 if not found then r:=jsonb_build_object('httpStatus',404,'code','catalog_product_not_found','message','Product was not found.','replayed',false);
 elsif p_expected_version is null or v.version<>p_expected_version then r:=jsonb_build_object('httpStatus',409,'code','catalog_version_conflict','message','Product changed; refresh before updating.','currentVersion',v.version,'replayed',false);
 else
   before:=jsonb_build_object('name',v.display_name,'status',v.lifecycle_status,'version',v.version);
   update commerce.products set display_name=trim(p_name),lifecycle_status=p_status,status=case when p_status='Retired' then 'Retired' else 'Active' end,version=version+1,updated_at_utc=now() where id=p_product returning * into v;
   if p_status='Retired' then
     update commerce.offers set status='Retired',version=version+1,updated_at_utc=now() where product_id=p_product and status<>'Retired';
     update commerce.bundles b set status='Retired',version=b.version+1,updated_at_utc=now()
       where b.status<>'Retired' and exists(select 1 from commerce.bundle_items bi join commerce.offers o on o.id=bi.offer_id where bi.bundle_id=b.id and o.product_id=p_product);
   end if;
   r:=jsonb_build_object('httpStatus',200,'code','ok','productId',v.id,'status',v.lifecycle_status,'version',v.version,'replayed',false);
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.product.update','commerce_product',p_product::text,p_reason,p_correlation,jsonb_build_object('before',before));
end $$;

create or replace function admin.update_commerce_catalog_offer(
 p_actor uuid,p_offer uuid,p_name varchar,p_duration smallint,p_status varchar,p_gift boolean,p_expected_version bigint,p_reason varchar,p_correlation uuid,p_key varchar,p_hash varchar
) returns jsonb language plpgsql security definer set search_path=admin,commerce,pg_temp as $$
declare op constant varchar:='commerce.catalog.offer.update'; r jsonb; v commerce.offers%rowtype; ps varchar; before jsonb;
begin
 if not admin.account_has_permission(p_actor,'commerce.catalog.write') then return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false); end if;
 if p_reason is null or length(trim(p_reason)) not between 10 and 1000 or p_name is null or length(trim(p_name)) not between 2 and 120 or p_duration not between 1 and 120 or p_status not in ('Hidden','Published','Retired') or p_gift is null then return jsonb_build_object('httpStatus',400,'code','catalog_offer_invalid','message','Offer mutation is invalid.','replayed',false); end if;
 r:=admin.commerce_catalog_v2_replay(p_actor,op,p_key,p_hash); if r is not null then return r; end if;
 perform pg_advisory_xact_lock(hashtextextended('commerce.catalog.offer:'||p_offer::text,0));
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
     if p_status='Retired' then
       update commerce.bundles b set status='Retired',version=b.version+1,updated_at_utc=now()
       where b.status<>'Retired' and exists(select 1 from commerce.bundle_items bi where bi.bundle_id=b.id and bi.offer_id=p_offer);
     end if;
     r:=jsonb_build_object('httpStatus',200,'code','ok','offerId',v.id,'status',v.status,'version',v.version,'replayed',false);
   end if;
 end if;
 return admin.commerce_catalog_v2_finish(p_actor,op,p_key,r,'commerce.catalog.offer.update','commerce_offer',p_offer::text,p_reason,p_correlation,jsonb_build_object('before',before));
end $$;

commit;
