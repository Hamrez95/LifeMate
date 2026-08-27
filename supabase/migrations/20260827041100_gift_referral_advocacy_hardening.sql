begin;

-- User-facing growth workflows are function-only. Edge runtime must not receive
-- broad table DML even though FORCE RLS is enabled.
revoke all on commerce.gift_intents from lifemate_edge_runtime;
revoke all on growth.referral_codes,growth.referral_attributions,growth.advocacy_submissions,
  growth.reward_rules,growth.reward_events from lifemate_edge_runtime;

drop policy if exists lifemate_edge_runtime_gift_intents on commerce.gift_intents;
drop policy if exists lifemate_edge_runtime_referral_codes on growth.referral_codes;
drop policy if exists lifemate_edge_runtime_referral_attributions on growth.referral_attributions;
drop policy if exists lifemate_edge_runtime_advocacy_submissions on growth.advocacy_submissions;

create or replace function growth.create_gift_intent(
  p_app_user_id uuid,
  p_recipient_phone_hash varchar,
  p_target_kind varchar,
  p_target_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,growth,commerce,identity,security,extensions,pg_temp
as $$
declare
  v_purchaser uuid;
  v_recipient uuid;
  v_existing commerce.gift_intents%rowtype;
  v_offer uuid;
  v_bundle uuid;
  v_abuse jsonb;
  v_abuse_action text;
  v_abuse_id uuid;
  v_id uuid;
  v_expires timestamptz:=now()+interval '24 hours';
  v_operation_key text;
  v_recent bigint;
begin
  v_purchaser:=growth.account_id_for_app_user(p_app_user_id);
  if v_purchaser is null then
    return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing','message','Account mapping is unavailable.');
  end if;
  if p_recipient_phone_hash is null or p_recipient_phone_hash !~ '^[0-9a-f]{64,128}$'
     or p_target_kind not in ('Offer','Bundle') or p_target_id is null
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','gift_request_invalid','message','Gift request is invalid.');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_purchaser::text||':gift:'||p_idempotency_key,0));
  select * into v_existing from commerce.gift_intents
  where purchaser_account_id=v_purchaser and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.');
    end if;
    return jsonb_build_object('httpStatus',200,'code','ok','giftIntentId',v_existing.id,'status',v_existing.status,'expiresAtUtc',v_existing.expires_at_utc,'replayed',true);
  end if;

  -- Hard operational ceiling independent of configurable abuse rules.
  select count(*) into v_recent from commerce.gift_intents
  where purchaser_account_id=v_purchaser and created_at_utc>=now()-interval '24 hours';
  if v_recent>=20 then
    return jsonb_build_object('httpStatus',429,'code','gift_velocity_limit','message','Gift creation is temporarily limited.');
  end if;

  select cp.account_id into v_recipient
  from identity.contact_points cp
  join identity.accounts a on a.id=cp.account_id and a.status='Active'
  where cp.kind='Phone' and cp.normalized_value_hash=lower(p_recipient_phone_hash)
    and cp.status='Verified' and cp.verified_at_utc is not null;
  if v_recipient is null or v_recipient=v_purchaser then
    return jsonb_build_object('httpStatus',404,'code','gift_recipient_not_eligible','message','The recipient is not eligible for this gift.');
  end if;

  if p_target_kind='Offer' then
    select o.id into v_offer from commerce.offers o
    where o.id=p_target_id and o.status='Published' and o.gift_eligible=true;
    if v_offer is null then
      return jsonb_build_object('httpStatus',404,'code','gift_target_unavailable','message','The selected gift is unavailable.');
    end if;
  else
    select b.id into v_bundle from commerce.bundles b
    where b.id=p_target_id and b.status='Published' and b.gift_eligible=true;
    if v_bundle is null then
      return jsonb_build_object('httpStatus',404,'code','gift_target_unavailable','message','The selected gift is unavailable.');
    end if;
  end if;

  v_operation_key:=v_recipient::text||':'||p_target_kind||':'||p_target_id::text;
  v_abuse:=security.evaluate_abuse_rules(
    v_purchaser,v_purchaser,'gift.create',v_operation_key,
    array['verified_recipient']::varchar[],p_idempotency_key,p_request_hash
  );
  if coalesce((v_abuse->>'httpStatus')::int,500)>=400 then return v_abuse; end if;
  v_abuse_action:=v_abuse->>'action';
  v_abuse_id:=nullif(v_abuse->>'decisionId','')::uuid;
  if v_abuse_action='Deny' then
    return jsonb_build_object('httpStatus',429,'code','gift_rate_limited','message','This gift request is not available right now.');
  elsif v_abuse_action='RequireApproval' then
    return jsonb_build_object('httpStatus',409,'code','gift_review_required','message','This gift request requires review before it can continue.');
  end if;

  insert into commerce.gift_intents(
    purchaser_account_id,recipient_account_id,recipient_phone_hash,target_kind,offer_id,bundle_id,
    abuse_decision_id,expires_at_utc,idempotency_key,request_hash
  ) values(
    v_purchaser,v_recipient,lower(p_recipient_phone_hash),p_target_kind,v_offer,v_bundle,
    v_abuse_id,v_expires,p_idempotency_key,p_request_hash
  ) returning id into v_id;

  perform security.record_abuse_event(v_purchaser,'gift.create',v_operation_key,'gift_created');
  return jsonb_build_object('httpStatus',201,'code','ok','giftIntentId',v_id,'status','AwaitingPayment','expiresAtUtc',v_expires,'replayed',false);
end $$;

create or replace function growth.attribute_referral(
  p_app_user_id uuid,
  p_code varchar,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,growth,identity,security,extensions,pg_temp
as $$
declare
  v_referred uuid;
  v_referral growth.referral_codes%rowtype;
  v_existing growth.referral_attributions%rowtype;
  v_abuse jsonb;
  v_action text;
  v_abuse_id uuid;
  v_id uuid;
  v_status text;
begin
  v_referred:=growth.account_id_for_app_user(p_app_user_id);
  if v_referred is null then
    return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing','message','Account mapping is unavailable.');
  end if;
  if p_code is null or upper(trim(p_code)) !~ '^[A-Z0-9]{8,32}$'
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','referral_request_invalid','message','Referral request is invalid.');
  end if;

  select * into v_existing from growth.referral_attributions where referred_account_id=v_referred;
  if found then
    return jsonb_build_object('httpStatus',409,'code','referral_already_attributed','message','A referral attribution already exists for this account.');
  end if;

  select * into v_referral from growth.referral_codes where code=upper(trim(p_code)) and status='Active';
  if not found or v_referral.account_id=v_referred then
    return jsonb_build_object('httpStatus',404,'code','referral_code_not_eligible','message','Referral code is not eligible.');
  end if;

  v_abuse:=security.evaluate_abuse_rules(
    v_referred,v_referred,'referral.attribute',v_referral.id::text,array[]::varchar[],p_idempotency_key,p_request_hash
  );
  if coalesce((v_abuse->>'httpStatus')::int,500)>=400 then return v_abuse; end if;
  v_action:=v_abuse->>'action';
  v_abuse_id:=nullif(v_abuse->>'decisionId','')::uuid;
  if v_action='Deny' then
    return jsonb_build_object('httpStatus',429,'code','referral_rate_limited','message','Referral attribution is not available right now.');
  end if;
  v_status:=case when v_action='RequireApproval' then 'PendingReview' else 'Attributed' end;
  insert into growth.referral_attributions(referral_code_id,referrer_account_id,referred_account_id,status,abuse_decision_id)
  values(v_referral.id,v_referral.account_id,v_referred,v_status,v_abuse_id)
  returning id into v_id;
  perform security.record_abuse_event(v_referred,'referral.attribute',v_referral.id::text,'referral_attributed');
  return jsonb_build_object('httpStatus',201,'code','ok','attributionId',v_id,'status',v_status,'replayed',false);
end $$;

create or replace function growth.submit_advocacy(
  p_app_user_id uuid,
  p_platform_code varchar,
  p_evidence_type varchar,
  p_evidence_reference_hash varchar,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,growth,security,extensions,pg_temp
as $$
declare
  v_account uuid;
  v_existing growth.advocacy_submissions%rowtype;
  v_abuse jsonb;
  v_action text;
  v_abuse_id uuid;
  v_id uuid;
  v_recent bigint;
begin
  v_account:=growth.account_id_for_app_user(p_app_user_id);
  if v_account is null then
    return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing','message','Account mapping is unavailable.');
  end if;
  if p_platform_code is null or lower(trim(p_platform_code)) !~ '^[a-z][a-z0-9._-]{1,39}$'
     or p_evidence_type not in ('PostUrl','StoryScreenshot','TagMention','CampaignParticipation','Other')
     or p_evidence_reference_hash is null or p_evidence_reference_hash !~ '^[0-9a-f]{64,128}$'
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','advocacy_request_invalid','message','Advocacy submission is invalid.');
  end if;

  select * into v_existing from growth.advocacy_submissions
  where account_id=v_account and platform_code=lower(trim(p_platform_code)) and evidence_reference_hash=lower(p_evidence_reference_hash);
  if found then
    return jsonb_build_object('httpStatus',200,'code','ok','submissionId',v_existing.id,'status',v_existing.status,'replayed',true);
  end if;

  select count(*) into v_recent from growth.advocacy_submissions
  where account_id=v_account and created_at_utc>=now()-interval '24 hours';
  if v_recent>=20 then
    return jsonb_build_object('httpStatus',429,'code','advocacy_velocity_limit','message','Advocacy submission is temporarily limited.');
  end if;

  v_abuse:=security.evaluate_abuse_rules(
    v_account,v_account,'advocacy.submit',lower(trim(p_platform_code))||':'||lower(p_evidence_reference_hash),
    array['explicit_user_submission']::varchar[],p_idempotency_key,p_request_hash
  );
  if coalesce((v_abuse->>'httpStatus')::int,500)>=400 then return v_abuse; end if;
  v_action:=v_abuse->>'action';
  v_abuse_id:=nullif(v_abuse->>'decisionId','')::uuid;
  if v_action='Deny' then
    return jsonb_build_object('httpStatus',429,'code','advocacy_rate_limited','message','Advocacy submission is not available right now.');
  end if;
  insert into growth.advocacy_submissions(
    account_id,platform_code,evidence_type,evidence_source,evidence_reference_hash,status,abuse_decision_id
  ) values(
    v_account,lower(trim(p_platform_code)),p_evidence_type,'UserSubmission',lower(p_evidence_reference_hash),'PendingReview',v_abuse_id
  ) returning id into v_id;
  perform security.record_abuse_event(v_account,'advocacy.submit',lower(p_evidence_reference_hash),'advocacy_submitted');
  return jsonb_build_object('httpStatus',201,'code','ok','submissionId',v_id,'status','PendingReview','replayed',false);
end $$;

revoke all on function growth.create_gift_intent(uuid,varchar,varchar,uuid,varchar,varchar) from public;
revoke all on function growth.attribute_referral(uuid,varchar,varchar,varchar) from public;
revoke all on function growth.submit_advocacy(uuid,varchar,varchar,varchar,varchar,varchar) from public;
grant execute on function growth.create_gift_intent(uuid,varchar,varchar,uuid,varchar,varchar) to lifemate_edge_runtime;
grant execute on function growth.attribute_referral(uuid,varchar,varchar,varchar) to lifemate_edge_runtime;
grant execute on function growth.submit_advocacy(uuid,varchar,varchar,varchar,varchar,varchar) to lifemate_edge_runtime;

commit;
