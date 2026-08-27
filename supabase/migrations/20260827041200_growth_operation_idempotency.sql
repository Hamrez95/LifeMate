begin;

alter table growth.referral_attributions
  add column if not exists idempotency_key varchar(180),
  add column if not exists request_hash varchar(128);

alter table growth.advocacy_submissions
  add column if not exists idempotency_key varchar(180),
  add column if not exists request_hash varchar(128);

alter table growth.referral_attributions
  drop constraint if exists ck_growth_referral_attributions_request_hash;
alter table growth.referral_attributions
  add constraint ck_growth_referral_attributions_request_hash
  check (request_hash is null or request_hash ~ '^[0-9a-f]{64,128}$');

alter table growth.advocacy_submissions
  drop constraint if exists ck_growth_advocacy_submissions_request_hash;
alter table growth.advocacy_submissions
  add constraint ck_growth_advocacy_submissions_request_hash
  check (request_hash is null or request_hash ~ '^[0-9a-f]{64,128}$');

create unique index if not exists uq_growth_referral_attributions_idempotency
  on growth.referral_attributions(referred_account_id,idempotency_key)
  where idempotency_key is not null;

create unique index if not exists uq_growth_advocacy_submissions_idempotency
  on growth.advocacy_submissions(account_id,idempotency_key)
  where idempotency_key is not null;

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

  perform pg_advisory_xact_lock(hashtextextended(v_referred::text||':referral',0));
  select * into v_existing
  from growth.referral_attributions
  where referred_account_id=v_referred;
  if found then
    if v_existing.idempotency_key=p_idempotency_key then
      if v_existing.request_hash<>p_request_hash then
        return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.');
      end if;
      return jsonb_build_object('httpStatus',200,'code','ok','attributionId',v_existing.id,'status',v_existing.status,'replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','referral_already_attributed','message','A referral attribution already exists for this account.');
  end if;

  select * into v_referral
  from growth.referral_codes
  where code=upper(trim(p_code)) and status='Active';
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
  insert into growth.referral_attributions(
    referral_code_id,referrer_account_id,referred_account_id,status,abuse_decision_id,
    idempotency_key,request_hash
  ) values(
    v_referral.id,v_referral.account_id,v_referred,v_status,v_abuse_id,
    p_idempotency_key,lower(p_request_hash)
  ) returning id into v_id;
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

  perform pg_advisory_xact_lock(hashtextextended(v_account::text||':advocacy:'||p_idempotency_key,0));
  select * into v_existing
  from growth.advocacy_submissions
  where account_id=v_account and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.');
    end if;
    return jsonb_build_object('httpStatus',200,'code','ok','submissionId',v_existing.id,'status',v_existing.status,'replayed',true);
  end if;

  select * into v_existing
  from growth.advocacy_submissions
  where account_id=v_account
    and platform_code=lower(trim(p_platform_code))
    and evidence_reference_hash=lower(p_evidence_reference_hash);
  if found then
    return jsonb_build_object('httpStatus',409,'code','advocacy_evidence_already_submitted','message','This advocacy evidence was already submitted.');
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
    account_id,platform_code,evidence_type,evidence_source,evidence_reference_hash,status,abuse_decision_id,
    idempotency_key,request_hash
  ) values(
    v_account,lower(trim(p_platform_code)),p_evidence_type,'UserSubmission',lower(p_evidence_reference_hash),'PendingReview',v_abuse_id,
    p_idempotency_key,lower(p_request_hash)
  ) returning id into v_id;
  perform security.record_abuse_event(v_account,'advocacy.submit',lower(p_evidence_reference_hash),'advocacy_submitted');
  return jsonb_build_object('httpStatus',201,'code','ok','submissionId',v_id,'status','PendingReview','replayed',false);
end $$;

revoke all on function growth.attribute_referral(uuid,varchar,varchar,varchar) from public;
revoke all on function growth.submit_advocacy(uuid,varchar,varchar,varchar,varchar,varchar) from public;
grant execute on function growth.attribute_referral(uuid,varchar,varchar,varchar) to lifemate_edge_runtime;
grant execute on function growth.submit_advocacy(uuid,varchar,varchar,varchar,varchar,varchar) to lifemate_edge_runtime;

commit;
