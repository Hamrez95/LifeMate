begin;

-- #618: transfer the remaining actual paid value from Period to CocoonMate.
create table if not exists commerce.subscription_payment_sources(
  subscription_id uuid primary key references commerce.subscriptions(id) on delete restrict,
  transaction_id uuid not null unique references commerce.transactions(id) on delete restrict,
  service_period_start_utc timestamptz not null,
  service_period_end_utc timestamptz not null,
  created_at_utc timestamptz not null default now(),
  check(service_period_end_utc>service_period_start_utc)
);

create table if not exists commerce.subscription_conversions(
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references identity.accounts(id) on delete restrict,
  source_subscription_id uuid not null unique references commerce.subscriptions(id) on delete restrict,
  source_transaction_id uuid not null references commerce.transactions(id) on delete restrict,
  target_subscription_id uuid not null unique references commerce.subscriptions(id) on delete restrict,
  source_product_id uuid not null references commerce.products(id) on delete restrict,
  target_product_id uuid not null references commerce.products(id) on delete restrict,
  currency varchar(3) not null check(currency ~ '^[A-Z]{3}$'),
  source_net_collected_minor bigint not null check(source_net_collected_minor>=0),
  transferable_value_minor bigint not null check(transferable_value_minor>=0),
  remaining_seconds bigint not null check(remaining_seconds>=0),
  service_period_seconds bigint not null check(service_period_seconds>0),
  converted_at_utc timestamptz not null default now(),
  correlation_id uuid not null,
  idempotency_key varchar(180) not null,
  request_hash varchar(128) not null check(request_hash ~ '^[0-9a-f]{64,128}$'),
  unique(account_id,idempotency_key)
);
create index if not exists ix_subscription_conversions_account on commerce.subscription_conversions(account_id,converted_at_utc desc);

alter table commerce.subscription_payment_sources enable row level security;
alter table commerce.subscription_payment_sources force row level security;
alter table commerce.subscription_conversions enable row level security;
alter table commerce.subscription_conversions force row level security;
revoke all on commerce.subscription_payment_sources,commerce.subscription_conversions from public,anon,authenticated;
grant select,insert on commerce.subscription_payment_sources,commerce.subscription_conversions to lifemate_edge_runtime;
grant select on commerce.subscription_conversions to lifemate_admin_runtime;
drop policy if exists subscription_payment_sources_edge on commerce.subscription_payment_sources;
drop policy if exists subscription_conversions_edge on commerce.subscription_conversions;
drop policy if exists subscription_conversions_admin_read on commerce.subscription_conversions;
create policy subscription_payment_sources_edge on commerce.subscription_payment_sources for all to lifemate_edge_runtime using(true) with check(true);
create policy subscription_conversions_edge on commerce.subscription_conversions for all to lifemate_edge_runtime using(true) with check(true);
create policy subscription_conversions_admin_read on commerce.subscription_conversions for select to lifemate_admin_runtime using(true);

create or replace function commerce.register_subscription_payment_source(p_subscription_id uuid,p_transaction_id uuid,p_period_start timestamptz,p_period_end timestamptz)
returns void language plpgsql security definer set search_path=pg_catalog,commerce,pg_temp as $$
declare v_tx record;
begin
  if p_period_start is null or p_period_end<=p_period_start then raise exception 'subscription_payment_source_invalid' using errcode='22023'; end if;
  perform 1 from commerce.subscriptions where id=p_subscription_id for update;
  if not found then raise exception 'subscription_not_found' using errcode='P0002'; end if;
  select * into v_tx from commerce.transaction_effective_state_v1 where transaction_id=p_transaction_id;
  if not found or v_tx.effective_normalized_status not in ('Succeeded','Refunded') or v_tx.net_collected_minor<=0 then
    raise exception 'transaction_not_settled' using errcode='23514';
  end if;
  insert into commerce.subscription_payment_sources values(p_subscription_id,p_transaction_id,p_period_start,p_period_end,now())
  on conflict(subscription_id) do update set transaction_id=excluded.transaction_id,service_period_start_utc=excluded.service_period_start_utc,service_period_end_utc=excluded.service_period_end_utc;
end $$;

create or replace function commerce.convert_period_to_cocoon(p_app_user_id uuid,p_idempotency_key varchar,p_request_hash varchar,p_correlation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,commerce,identity,pg_temp as $$
declare
  a uuid; period_product uuid; cocoon_product uuid; source commerce.subscriptions%rowtype;
  payment commerce.subscription_payment_sources%rowtype; tx record; prior commerce.subscription_conversions%rowtype;
  target_id uuid; now_utc timestamptz:=now(); total_s bigint; remaining_s bigint; transfer_minor bigint;
begin
  a:=identity.account_id_for_legacy_app_user(p_app_user_id);
  if a is null then return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing'); end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180 or p_request_hash !~ '^[0-9a-f]{64,128}$' or p_correlation_id is null then
    return jsonb_build_object('httpStatus',400,'code','conversion_request_invalid');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(a::text||':period-cocoon-conversion',0));
  select * into prior from commerce.subscription_conversions where account_id=a and idempotency_key=p_idempotency_key;
  if found then
    if prior.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict'); end if;
    return jsonb_build_object('httpStatus',200,'code','ok','conversionId',prior.id,'targetSubscriptionId',prior.target_subscription_id,'transferableValueMinor',prior.transferable_value_minor,'currency',prior.currency,'replayed',true);
  end if;
  select id into period_product from commerce.products where code='period-calendar' and lifecycle_status<>'Retired';
  select id into cocoon_product from commerce.products where code='cocoonmate' and lifecycle_status<>'Retired';
  if period_product is null or cocoon_product is null then return jsonb_build_object('httpStatus',409,'code','conversion_products_unavailable'); end if;
  select * into source from commerce.subscriptions where owner_account_id=a and product_id=period_product and status='Active' and starts_at_utc<=now_utc and current_period_end_utc>now_utc order by current_period_end_utc desc limit 1 for update;
  if not found then return jsonb_build_object('httpStatus',409,'code','period_paid_subscription_required'); end if;
  if exists(select 1 from commerce.subscription_conversions where source_subscription_id=source.id) then return jsonb_build_object('httpStatus',409,'code','period_subscription_already_converted'); end if;
  if exists(select 1 from commerce.subscriptions where owner_account_id=a and product_id=cocoon_product and status='Active' and (current_period_end_utc is null or current_period_end_utc>now_utc)) then return jsonb_build_object('httpStatus',409,'code','cocoon_subscription_already_active'); end if;
  select * into payment from commerce.subscription_payment_sources where subscription_id=source.id;
  if not found then return jsonb_build_object('httpStatus',409,'code','paid_value_provenance_missing'); end if;
  select * into tx from commerce.transaction_effective_state_v1 where transaction_id=payment.transaction_id;
  if not found or tx.effective_normalized_status not in ('Succeeded','Refunded') or tx.net_collected_minor<=0 then return jsonb_build_object('httpStatus',409,'code','paid_value_not_transferable'); end if;
  total_s:=floor(extract(epoch from(payment.service_period_end_utc-payment.service_period_start_utc)))::bigint;
  remaining_s:=greatest(0,floor(extract(epoch from(payment.service_period_end_utc-now_utc)))::bigint);
  if total_s<=0 or remaining_s<=0 then return jsonb_build_object('httpStatus',409,'code','paid_period_expired'); end if;
  transfer_minor:=floor(tx.net_collected_minor::numeric*remaining_s::numeric/total_s::numeric)::bigint;
  if transfer_minor<=0 then return jsonb_build_object('httpStatus',409,'code','paid_value_exhausted'); end if;
  insert into commerce.subscriptions(payer_account_id,owner_account_id,beneficiary_person_id,product_id,plan_id,provider,provider_reference_hash,status,starts_at_utc,current_period_end_utc)
  values(source.payer_account_id,source.owner_account_id,source.beneficiary_person_id,cocoon_product,source.plan_id,'InternalConversion',md5(source.id::text||p_correlation_id::text),'Active',now_utc,payment.service_period_end_utc) returning id into target_id;
  update commerce.subscriptions set status='Cancelled',cancelled_at_utc=now_utc,updated_at_utc=now_utc where id=source.id;
  insert into commerce.subscription_conversions(account_id,source_subscription_id,source_transaction_id,target_subscription_id,source_product_id,target_product_id,currency,source_net_collected_minor,transferable_value_minor,remaining_seconds,service_period_seconds,converted_at_utc,correlation_id,idempotency_key,request_hash)
  values(a,source.id,payment.transaction_id,target_id,period_product,cocoon_product,tx.currency,tx.net_collected_minor,transfer_minor,remaining_s,total_s,now_utc,p_correlation_id,p_idempotency_key,p_request_hash) returning * into prior;
  return jsonb_build_object('httpStatus',200,'code','ok','conversionId',prior.id,'sourceSubscriptionId',source.id,'targetSubscriptionId',target_id,'transferableValueMinor',transfer_minor,'currency',tx.currency,'targetEndsAtUtc',payment.service_period_end_utc,'replayed',false);
end $$;

revoke all on function commerce.register_subscription_payment_source(uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function commerce.convert_period_to_cocoon(uuid,varchar,varchar,uuid) from public,anon,authenticated;
grant execute on function commerce.register_subscription_payment_source(uuid,uuid,timestamptz,timestamptz) to lifemate_edge_runtime;
grant execute on function commerce.convert_period_to_cocoon(uuid,varchar,varchar,uuid) to lifemate_edge_runtime;
commit;
