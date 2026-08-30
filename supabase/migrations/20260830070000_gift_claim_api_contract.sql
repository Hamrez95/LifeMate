begin;

-- Harden the gift lifecycle introduced in 20260830061000 without changing
-- health permissions, consent, relationships, or reproductive-health data.
create or replace function growth.mark_subscription_gift_paid(
  p_gift_intent_id uuid,p_transaction_id uuid,p_claim_token_hash varchar,p_claim_ttl_hours integer default 168
) returns jsonb language plpgsql security definer set search_path=pg_catalog,growth,commerce,pg_temp as $$
declare g commerce.gift_intents%rowtype; o commerce.offers%rowtype; p commerce.prices%rowtype; tx record; now_utc timestamptz:=now();
begin
  if p_claim_token_hash is null or p_claim_token_hash !~ '^[0-9a-f]{64,128}$' or p_claim_ttl_hours not between 1 and 720 then return jsonb_build_object('httpStatus',400,'code','gift_payment_request_invalid'); end if;
  select * into g from commerce.gift_intents where id=p_gift_intent_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','gift_not_found'); end if;
  if g.status in ('Paid','PendingClaim','Claimed','Fulfilled') then
    if g.transaction_id=p_transaction_id then return jsonb_build_object('httpStatus',200,'code','ok','giftIntentId',g.id,'status',g.status,'replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','gift_payment_conflict');
  end if;
  if g.status<>'AwaitingPayment' or g.expires_at_utc<=now_utc or g.target_kind<>'Offer' then return jsonb_build_object('httpStatus',409,'code','gift_not_payable'); end if;
  select * into o from commerce.offers where id=g.offer_id and status='Published'; if not found then return jsonb_build_object('httpStatus',409,'code','gift_offer_unavailable'); end if;
  select * into p from commerce.prices where offer_id=o.id and status='Active' and effective_from_utc<=now_utc and (effective_to_utc is null or effective_to_utc>now_utc) order by effective_from_utc desc limit 1;
  if not found then return jsonb_build_object('httpStatus',409,'code','gift_price_unavailable'); end if;
  select * into tx from commerce.transaction_effective_state_v1 where transaction_id=p_transaction_id;
  if not found or tx.effective_normalized_status<>'Succeeded' or tx.net_collected_minor<>p.amount_minor or tx.currency<>p.currency or tx.account_id<>g.purchaser_account_id or tx.product_id<>o.product_id then return jsonb_build_object('httpStatus',409,'code','gift_payment_not_settled'); end if;
  update commerce.gift_intents set status='PendingClaim',transaction_id=p_transaction_id,price_id=p.id,price_amount_minor=p.amount_minor,price_currency=p.currency,claim_token_hash=lower(p_claim_token_hash),paid_at_utc=now_utc,claim_expires_at_utc=now_utc+make_interval(hours=>p_claim_ttl_hours),updated_at_utc=now_utc,version=version+1 where id=g.id returning * into g;
  return jsonb_build_object('httpStatus',200,'code','ok','giftIntentId',g.id,'status',g.status,'claimExpiresAtUtc',g.claim_expires_at_utc,'replayed',false);
end $$;

-- Purchaser-facing state deliberately contains no recipient product usage,
-- claim detail, reproductive state, or health information.
create or replace function growth.gift_status_for_purchaser(p_app_user_id uuid,p_gift_intent_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,growth,commerce,identity,pg_temp as $$
declare a uuid; g commerce.gift_intents%rowtype; public_status text;
begin
  a:=identity.account_id_for_legacy_app_user(p_app_user_id);
  select * into g from commerce.gift_intents where id=p_gift_intent_id and purchaser_account_id=a;
  if not found then return jsonb_build_object('httpStatus',404,'code','gift_not_found'); end if;
  public_status:=case when g.status='AwaitingPayment' then 'AwaitingPayment' when g.status in ('Paid','PendingClaim') then 'Sent' when g.status in ('Claimed','Fulfilled') then 'Completed' when g.status='Refunded' then 'Refunded' else 'Unavailable' end;
  return jsonb_build_object('httpStatus',200,'code','ok','giftIntentId',g.id,'status',public_status,'expiresAtUtc',g.expires_at_utc);
end $$;

revoke all on function growth.gift_status_for_purchaser(uuid,uuid) from public;
grant execute on function growth.gift_status_for_purchaser(uuid,uuid) to lifemate_edge_runtime;
commit;
