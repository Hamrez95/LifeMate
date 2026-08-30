begin;

alter table commerce.gift_intents
  add column if not exists price_id uuid references commerce.prices(id) on delete restrict,
  add column if not exists price_amount_minor bigint check(price_amount_minor is null or price_amount_minor>=0),
  add column if not exists price_currency varchar(3) check(price_currency is null or price_currency ~ '^[A-Z]{3}$'),
  add column if not exists claim_token_hash varchar(128) check(claim_token_hash is null or claim_token_hash ~ '^[0-9a-f]{64,128}$'),
  add column if not exists paid_at_utc timestamptz,
  add column if not exists claim_expires_at_utc timestamptz,
  add column if not exists claimed_at_utc timestamptz,
  add column if not exists resulting_subscription_id uuid references commerce.subscriptions(id) on delete restrict;

do $$ begin
  if exists(select 1 from pg_constraint where conrelid='commerce.gift_intents'::regclass and conname='gift_intents_status_check') then
    alter table commerce.gift_intents drop constraint gift_intents_status_check;
  end if;
end $$;
alter table commerce.gift_intents add constraint gift_intents_status_check
  check(status in ('AwaitingPayment','Paid','PendingClaim','Claimed','Fulfilled','Cancelled','Expired','Refunded'));
create unique index if not exists ux_gift_claim_token_hash on commerce.gift_intents(claim_token_hash) where claim_token_hash is not null;

create or replace function growth.mark_subscription_gift_paid(
  p_gift_intent_id uuid,p_transaction_id uuid,p_claim_token_hash varchar,p_claim_ttl_hours integer default 168
) returns jsonb language plpgsql security definer set search_path=pg_catalog,growth,commerce,pg_temp as $$
declare g commerce.gift_intents%rowtype; o commerce.offers%rowtype; p commerce.prices%rowtype; tx record; now_utc timestamptz:=now();
begin
  if p_claim_token_hash is null or p_claim_token_hash !~ '^[0-9a-f]{64,128}$' or p_claim_ttl_hours not between 1 and 720 then
    return jsonb_build_object('httpStatus',400,'code','gift_payment_request_invalid');
  end if;
  select * into g from commerce.gift_intents where id=p_gift_intent_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','gift_not_found'); end if;
  if g.status in ('Paid','PendingClaim','Claimed','Fulfilled') then
    if g.transaction_id=p_transaction_id then return jsonb_build_object('httpStatus',200,'code','ok','giftIntentId',g.id,'status',g.status,'replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','gift_payment_conflict');
  end if;
  if g.status<>'AwaitingPayment' or g.expires_at_utc<=now_utc or g.target_kind<>'Offer' then
    return jsonb_build_object('httpStatus',409,'code','gift_not_payable');
  end if;
  select * into o from commerce.offers where id=g.offer_id and status='Published';
  if not found then return jsonb_build_object('httpStatus',409,'code','gift_offer_unavailable'); end if;
  select * into p from commerce.prices where offer_id=o.id and status='Active' and effective_from_utc<=now_utc and (effective_to_utc is null or effective_to_utc>now_utc) order by effective_from_utc desc limit 1;
  if not found then return jsonb_build_object('httpStatus',409,'code','gift_price_unavailable'); end if;
  select * into tx from commerce.transaction_effective_state_v1 where transaction_id=p_transaction_id;
  if not found or tx.effective_normalized_status<>'Succeeded' or tx.net_collected_minor<>p.amount_minor or tx.currency<>p.currency then
    return jsonb_build_object('httpStatus',409,'code','gift_payment_not_settled');
  end if;
  update commerce.gift_intents set status='PendingClaim',transaction_id=p_transaction_id,price_id=p.id,
    price_amount_minor=p.amount_minor,price_currency=p.currency,claim_token_hash=lower(p_claim_token_hash),
    paid_at_utc=now_utc,claim_expires_at_utc=now_utc+make_interval(hours=>p_claim_ttl_hours),updated_at_utc=now_utc,version=version+1
  where id=g.id returning * into g;
  return jsonb_build_object('httpStatus',200,'code','ok','giftIntentId',g.id,'status',g.status,'claimExpiresAtUtc',g.claim_expires_at_utc,'replayed',false);
end $$;

create or replace function growth.claim_subscription_gift(p_app_user_id uuid,p_claim_token_hash varchar)
returns jsonb language plpgsql security definer set search_path=pg_catalog,growth,commerce,identity,core,pg_temp as $$
declare a uuid; person uuid; g commerce.gift_intents%rowtype; o commerce.offers%rowtype; product commerce.products%rowtype; existing commerce.subscriptions%rowtype; sub_id uuid; now_utc timestamptz:=now(); new_end timestamptz;
begin
  a:=identity.account_id_for_legacy_app_user(p_app_user_id);
  if a is null then return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing'); end if;
  if p_claim_token_hash is null or p_claim_token_hash !~ '^[0-9a-f]{64,128}$' then return jsonb_build_object('httpStatus',400,'code','gift_claim_invalid'); end if;
  perform pg_advisory_xact_lock(hashtextextended(a::text||':gift-claim',0));
  select * into g from commerce.gift_intents where claim_token_hash=lower(p_claim_token_hash) for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','gift_claim_not_found'); end if;
  if g.recipient_account_id<>a then return jsonb_build_object('httpStatus',403,'code','gift_wrong_recipient'); end if;
  if g.status in ('Claimed','Fulfilled') then return jsonb_build_object('httpStatus',200,'code','ok','status','claimed','subscriptionId',g.resulting_subscription_id,'replayed',true); end if;
  if g.status<>'PendingClaim' then return jsonb_build_object('httpStatus',409,'code','gift_not_claimable'); end if;
  if g.claim_expires_at_utc is null or g.claim_expires_at_utc<=now_utc then
    update commerce.gift_intents set status='Expired',updated_at_utc=now_utc,version=version+1 where id=g.id;
    return jsonb_build_object('httpStatus',410,'code','gift_claim_expired');
  end if;
  select * into o from commerce.offers where id=g.offer_id and status='Published';
  if not found then return jsonb_build_object('httpStatus',409,'code','gift_offer_unavailable'); end if;
  select * into product from commerce.products where id=o.product_id and lifecycle_status='Published';
  if not found then return jsonb_build_object('httpStatus',409,'code','gift_product_unavailable'); end if;
  select l.person_id into person from core.account_person_links l where l.account_id=a and l.link_type='Self' and l.status='Active' order by l.created_at_utc limit 1;
  if person is null then return jsonb_build_object('httpStatus',409,'code','identity_person_mapping_missing'); end if;

  -- Recipient-controlled claim is the only activation step, including Period/CocoonMate.
  select * into existing from commerce.subscriptions where owner_account_id=a and product_id=product.id and status='Active'
    and (current_period_end_utc is null or current_period_end_utc>now_utc) order by current_period_end_utc desc nulls first limit 1 for update;
  if found and existing.current_period_end_utc is null then return jsonb_build_object('httpStatus',409,'code','gift_overlap_nonexpiring'); end if;
  if found then
    new_end:=existing.current_period_end_utc+make_interval(months=>o.duration_months);
    update commerce.subscriptions set current_period_end_utc=new_end,updated_at_utc=now_utc where id=existing.id;
    sub_id:=existing.id;
  else
    new_end:=now_utc+make_interval(months=>o.duration_months);
    insert into commerce.subscriptions(payer_account_id,owner_account_id,beneficiary_person_id,product_id,plan_id,provider,provider_reference_hash,status,starts_at_utc,current_period_end_utc)
    values(g.purchaser_account_id,a,person,product.id,o.plan_id,'InternalGift',md5(g.id::text||a::text),'Active',now_utc,new_end) returning id into sub_id;
  end if;
  update commerce.gift_intents set status='Claimed',claimed_at_utc=now_utc,fulfilled_at_utc=now_utc,resulting_subscription_id=sub_id,updated_at_utc=now_utc,version=version+1 where id=g.id;
  return jsonb_build_object('httpStatus',200,'code','ok','status','claimed','subscriptionId',sub_id,'accessEndsAtUtc',new_end,'replayed',false);
end $$;

revoke all on function growth.mark_subscription_gift_paid(uuid,uuid,varchar,integer) from public,anon,authenticated;
revoke all on function growth.claim_subscription_gift(uuid,varchar) from public,anon,authenticated;
grant execute on function growth.mark_subscription_gift_paid(uuid,uuid,varchar,integer) to lifemate_edge_runtime;
grant execute on function growth.claim_subscription_gift(uuid,varchar) to lifemate_edge_runtime;
commit;
