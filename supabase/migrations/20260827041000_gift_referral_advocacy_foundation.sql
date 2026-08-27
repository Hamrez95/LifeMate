begin;

create schema if not exists growth;
revoke all on schema growth from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on schema growth from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on schema growth from authenticated';
  end if;
end $$;

grant usage on schema growth to lifemate_edge_runtime,lifemate_admin_runtime;

create table if not exists commerce.gift_intents (
  id uuid primary key default gen_random_uuid(),
  purchaser_account_id uuid not null references identity.accounts(id) on delete restrict,
  recipient_account_id uuid not null references identity.accounts(id) on delete restrict,
  recipient_phone_hash varchar(128) not null check (recipient_phone_hash ~ '^[0-9a-f]{64,128}$'),
  target_kind varchar(16) not null check (target_kind in ('Offer','Bundle')),
  offer_id uuid references commerce.offers(id) on delete restrict,
  bundle_id uuid references commerce.bundles(id) on delete restrict,
  status varchar(24) not null default 'AwaitingPayment'
    check (status in ('AwaitingPayment','Paid','Fulfilled','Cancelled','Expired')),
  order_id uuid references commerce.orders(id) on delete set null,
  transaction_id uuid references commerce.transactions(id) on delete set null,
  abuse_decision_id uuid references security.abuse_decisions(id) on delete restrict,
  expires_at_utc timestamptz not null,
  fulfilled_at_utc timestamptz,
  idempotency_key varchar(180) not null,
  request_hash varchar(128) not null check (request_hash ~ '^[0-9a-f]{64,128}$'),
  version bigint not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (purchaser_account_id <> recipient_account_id),
  check (
    (target_kind='Offer' and offer_id is not null and bundle_id is null)
    or (target_kind='Bundle' and bundle_id is not null and offer_id is null)
  ),
  unique(purchaser_account_id,idempotency_key)
);
create index if not exists ix_commerce_gift_intents_purchaser
  on commerce.gift_intents(purchaser_account_id,created_at_utc desc,id desc);
create index if not exists ix_commerce_gift_intents_recipient
  on commerce.gift_intents(recipient_account_id,status,created_at_utc desc,id desc);
create index if not exists ix_commerce_gift_intents_expiry
  on commerce.gift_intents(expires_at_utc,id)
  where status='AwaitingPayment';

create table if not exists growth.referral_codes (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references identity.accounts(id) on delete restrict,
  code varchar(32) not null unique check (code ~ '^[A-Z0-9]{8,32}$'),
  status varchar(16) not null default 'Active' check (status in ('Active','Retired')),
  created_at_utc timestamptz not null default now(),
  retired_at_utc timestamptz
);
create unique index if not exists uq_growth_referral_codes_active_account
  on growth.referral_codes(account_id) where status='Active';

create table if not exists growth.referral_attributions (
  id uuid primary key default gen_random_uuid(),
  referral_code_id uuid not null references growth.referral_codes(id) on delete restrict,
  referrer_account_id uuid not null references identity.accounts(id) on delete restrict,
  referred_account_id uuid not null references identity.accounts(id) on delete restrict,
  status varchar(24) not null default 'Attributed'
    check (status in ('Attributed','PendingReview','Qualified','Rewarded','Rejected')),
  abuse_decision_id uuid references security.abuse_decisions(id) on delete restrict,
  attributed_at_utc timestamptz not null default now(),
  qualified_at_utc timestamptz,
  rewarded_at_utc timestamptz,
  rule_version bigint,
  check (referrer_account_id <> referred_account_id),
  unique(referred_account_id)
);
create index if not exists ix_growth_referral_attributions_referrer
  on growth.referral_attributions(referrer_account_id,status,attributed_at_utc desc,id desc);

create table if not exists growth.advocacy_submissions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references identity.accounts(id) on delete restrict,
  platform_code varchar(40) not null check (platform_code ~ '^[a-z][a-z0-9._-]{1,39}$'),
  evidence_type varchar(32) not null
    check (evidence_type in ('PostUrl','StoryScreenshot','TagMention','CampaignParticipation','Other')),
  evidence_source varchar(32) not null
    check (evidence_source in ('UserSubmission','OfficialIntegration')),
  evidence_reference_hash varchar(128) not null check (evidence_reference_hash ~ '^[0-9a-f]{64,128}$'),
  status varchar(24) not null default 'PendingReview'
    check (status in ('PendingReview','Verified','Rejected','Rewarded')),
  abuse_decision_id uuid references security.abuse_decisions(id) on delete restrict,
  verified_metrics_json jsonb,
  reviewed_by_account_id uuid references identity.accounts(id) on delete set null,
  reviewed_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (verified_metrics_json is null or jsonb_typeof(verified_metrics_json)='object'),
  unique(account_id,platform_code,evidence_reference_hash)
);
create index if not exists ix_growth_advocacy_submissions_review
  on growth.advocacy_submissions(status,created_at_utc,id);

create table if not exists growth.reward_rules (
  id uuid primary key default gen_random_uuid(),
  code varchar(80) not null unique check (code ~ '^[a-z][a-z0-9._-]{2,79}$'),
  trigger_kind varchar(24) not null check (trigger_kind in ('Referral','Advocacy','Gift','Campaign')),
  reward_kind varchar(32) not null
    check (reward_kind in ('Discount','GiftEntitlement','RaffleEligibility','CharityImpact')),
  reward_config jsonb not null check (jsonb_typeof(reward_config)='object'),
  max_issues_per_account integer check (max_issues_per_account is null or max_issues_per_account between 1 and 100000),
  status varchar(16) not null default 'Draft' check (status in ('Draft','Active','Paused','Retired')),
  version bigint not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);

create table if not exists growth.reward_events (
  id uuid primary key default gen_random_uuid(),
  beneficiary_account_id uuid not null references identity.accounts(id) on delete restrict,
  source_kind varchar(24) not null check (source_kind in ('Referral','Advocacy','Gift','Campaign')),
  source_id uuid not null,
  reward_rule_id uuid not null references growth.reward_rules(id) on delete restrict,
  reward_rule_version bigint not null check (reward_rule_version >= 1),
  reward_kind varchar(32) not null
    check (reward_kind in ('Discount','GiftEntitlement','RaffleEligibility','CharityImpact')),
  status varchar(16) not null default 'Pending' check (status in ('Pending','Issued','Rejected','Reversed')),
  provenance_hash varchar(128) not null check (provenance_hash ~ '^[0-9a-f]{64,128}$'),
  reward_reference_hash varchar(128),
  abuse_decision_id uuid references security.abuse_decisions(id) on delete restrict,
  created_at_utc timestamptz not null default now(),
  issued_at_utc timestamptz,
  reversed_at_utc timestamptz,
  check (reward_reference_hash is null or reward_reference_hash ~ '^[0-9a-f]{64,128}$'),
  unique(source_kind,source_id,reward_rule_id,beneficiary_account_id)
);
create index if not exists ix_growth_reward_events_beneficiary
  on growth.reward_events(beneficiary_account_id,created_at_utc desc,id desc);

alter table commerce.gift_intents enable row level security;
alter table commerce.gift_intents force row level security;
alter table growth.referral_codes enable row level security;
alter table growth.referral_codes force row level security;
alter table growth.referral_attributions enable row level security;
alter table growth.referral_attributions force row level security;
alter table growth.advocacy_submissions enable row level security;
alter table growth.advocacy_submissions force row level security;
alter table growth.reward_rules enable row level security;
alter table growth.reward_rules force row level security;
alter table growth.reward_events enable row level security;
alter table growth.reward_events force row level security;

revoke all on commerce.gift_intents from public;
revoke all on growth.referral_codes,growth.referral_attributions,growth.advocacy_submissions,
  growth.reward_rules,growth.reward_events from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on commerce.gift_intents from anon';
    execute 'revoke all on growth.referral_codes,growth.referral_attributions,growth.advocacy_submissions,growth.reward_rules,growth.reward_events from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on commerce.gift_intents from authenticated';
    execute 'revoke all on growth.referral_codes,growth.referral_attributions,growth.advocacy_submissions,growth.reward_rules,growth.reward_events from authenticated';
  end if;
end $$;

create policy lifemate_edge_runtime_gift_intents on commerce.gift_intents
  for all to lifemate_edge_runtime using (true) with check (true);
create policy lifemate_admin_runtime_gift_intents on commerce.gift_intents
  for select to lifemate_admin_runtime using (true);
create policy lifemate_edge_runtime_referral_codes on growth.referral_codes
  for all to lifemate_edge_runtime using (true) with check (true);
create policy lifemate_admin_runtime_referral_codes on growth.referral_codes
  for select to lifemate_admin_runtime using (true);
create policy lifemate_edge_runtime_referral_attributions on growth.referral_attributions
  for all to lifemate_edge_runtime using (true) with check (true);
create policy lifemate_admin_runtime_referral_attributions on growth.referral_attributions
  for select to lifemate_admin_runtime using (true);
create policy lifemate_edge_runtime_advocacy_submissions on growth.advocacy_submissions
  for all to lifemate_edge_runtime using (true) with check (true);
create policy lifemate_admin_runtime_advocacy_submissions on growth.advocacy_submissions
  for select to lifemate_admin_runtime using (true);
create policy lifemate_admin_runtime_reward_rules on growth.reward_rules
  for select to lifemate_admin_runtime using (true);
create policy lifemate_admin_runtime_reward_events on growth.reward_events
  for select to lifemate_admin_runtime using (true);

grant select,insert,update on commerce.gift_intents to lifemate_edge_runtime;
grant select on commerce.gift_intents to lifemate_admin_runtime;
grant select,insert,update on growth.referral_codes,growth.referral_attributions,growth.advocacy_submissions to lifemate_edge_runtime;
grant select on growth.referral_codes,growth.referral_attributions,growth.advocacy_submissions,growth.reward_rules,growth.reward_events to lifemate_admin_runtime;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('growth.rewards.read','growth','STANDARD',true,'Read privacy-minimized gift, referral, advocacy and reward operations'),
('growth.rewards.write','growth','HIGH_RISK',true,'Manage reward rules and reviewed reward issuance through audited server workflows')
on conflict (code) do update set description=excluded.description,updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join (values ('growth.rewards.read'),('growth.rewards.write')) p(code)
where r.code in ('founder','super_admin')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'growth.rewards.read'
from admin.roles r
where r.code in ('marketing','finance','support')
on conflict do nothing;

create or replace function growth.account_id_for_app_user(p_app_user_id uuid)
returns uuid
language sql
security definer
stable
set search_path=pg_catalog,identity,lifemate,pg_temp
as $$
  select identity.account_id_for_legacy_app_user(p_app_user_id)
$$;
revoke all on function growth.account_id_for_app_user(uuid) from public;
grant execute on function growth.account_id_for_app_user(uuid) to lifemate_edge_runtime;

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

  select cp.account_id into v_recipient
  from identity.contact_points cp
  join identity.accounts a on a.id=cp.account_id and a.status='Active'
  where cp.kind='Phone' and cp.normalized_value_hash=lower(p_recipient_phone_hash) and cp.status='Verified';
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

  v_abuse:=security.evaluate_abuse_rules(
    v_purchaser,v_purchaser,'gift.create',
    v_recipient::text||':'||p_target_kind||':'||p_target_id::text,
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

  perform security.record_abuse_event(
    v_purchaser,'gift.create',v_purchaser,
    v_recipient::text||':'||p_target_kind||':'||p_target_id::text,p_idempotency_key
  );

  return jsonb_build_object('httpStatus',201,'code','ok','giftIntentId',v_id,'status','AwaitingPayment','expiresAtUtc',v_expires,'replayed',false);
end $$;
revoke all on function growth.create_gift_intent(uuid,varchar,varchar,uuid,varchar,varchar) from public;
grant execute on function growth.create_gift_intent(uuid,varchar,varchar,uuid,varchar,varchar) to lifemate_edge_runtime;

create or replace function growth.ensure_referral_code(p_app_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,growth,identity,extensions,pg_temp
as $$
declare
  v_account uuid;
  v_existing growth.referral_codes%rowtype;
  v_code text;
  v_id uuid;
begin
  v_account:=growth.account_id_for_app_user(p_app_user_id);
  if v_account is null then
    return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing','message','Account mapping is unavailable.');
  end if;
  select * into v_existing from growth.referral_codes where account_id=v_account and status='Active';
  if found then
    return jsonb_build_object('httpStatus',200,'code','ok','referralCodeId',v_existing.id,'codeValue',v_existing.code,'created',false);
  end if;
  for i in 1..8 loop
    v_code:=upper(encode(extensions.gen_random_bytes(6),'hex'));
    begin
      insert into growth.referral_codes(account_id,code) values(v_account,v_code) returning id into v_id;
      return jsonb_build_object('httpStatus',201,'code','ok','referralCodeId',v_id,'codeValue',v_code,'created',true);
    exception when unique_violation then
      select * into v_existing from growth.referral_codes where account_id=v_account and status='Active';
      if found then
        return jsonb_build_object('httpStatus',200,'code','ok','referralCodeId',v_existing.id,'codeValue',v_existing.code,'created',false);
      end if;
    end;
  end loop;
  return jsonb_build_object('httpStatus',503,'code','referral_code_unavailable','message','Referral code could not be created.');
end $$;
revoke all on function growth.ensure_referral_code(uuid) from public;
grant execute on function growth.ensure_referral_code(uuid) to lifemate_edge_runtime;

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
    return jsonb_build_object('httpStatus',200,'code','ok','attributionId',v_existing.id,'status',v_existing.status,'replayed',true);
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
  perform security.record_abuse_event(v_referred,'referral.attribute',v_referred,v_referral.id::text,p_idempotency_key);
  return jsonb_build_object('httpStatus',201,'code','ok','attributionId',v_id,'status',v_status,'replayed',false);
end $$;
revoke all on function growth.attribute_referral(uuid,varchar,varchar,varchar) from public;
grant execute on function growth.attribute_referral(uuid,varchar,varchar,varchar) to lifemate_edge_runtime;

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
  perform security.record_abuse_event(v_account,'advocacy.submit',v_account,lower(p_evidence_reference_hash),p_idempotency_key);
  return jsonb_build_object('httpStatus',201,'code','ok','submissionId',v_id,'status','PendingReview','replayed',false);
end $$;
revoke all on function growth.submit_advocacy(uuid,varchar,varchar,varchar,varchar,varchar) from public;
grant execute on function growth.submit_advocacy(uuid,varchar,varchar,varchar,varchar,varchar) to lifemate_edge_runtime;

create or replace function growth.list_reward_events_for_app_user(p_app_user_id uuid)
returns table(
  id uuid, source_kind varchar, reward_kind varchar, status varchar,
  created_at_utc timestamptz, issued_at_utc timestamptz
)
language sql
security definer
stable
set search_path=pg_catalog,growth,pg_temp
as $$
  select e.id,e.source_kind,e.reward_kind,e.status,e.created_at_utc,e.issued_at_utc
  from growth.reward_events e
  where e.beneficiary_account_id=growth.account_id_for_app_user(p_app_user_id)
  order by e.created_at_utc desc,e.id desc
  limit 100
$$;
revoke all on function growth.list_reward_events_for_app_user(uuid) from public;
grant execute on function growth.list_reward_events_for_app_user(uuid) to lifemate_edge_runtime;

commit;
