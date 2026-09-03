begin;

create schema if not exists messaging;
revoke all on schema messaging from public;

do $$
begin
  if to_regrole('anon') is not null then execute 'revoke all on schema messaging from anon'; end if;
  if to_regrole('authenticated') is not null then execute 'revoke all on schema messaging from authenticated'; end if;
end $$;

grant usage on schema messaging to lifemate_admin_runtime,lifemate_worker_runtime;

create table if not exists messaging.push_registrations (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references identity.accounts(id) on delete cascade,
  product_code varchar(64) not null check (product_code ~ '^[a-z0-9][a-z0-9_.:-]{0,63}$'),
  platform varchar(16) not null check (platform in ('Android','iOS','Web')),
  provider varchar(40) not null check (provider ~ '^[a-z0-9][a-z0-9_.-]{1,39}$'),
  token_hash varchar(128) not null check (token_hash ~ '^[0-9a-f]{64,128}$'),
  token_ciphertext bytea not null,
  token_nonce_b64 varchar(64) not null,
  encryption_key_version smallint not null check (encryption_key_version between 1 and 32767),
  status varchar(16) not null default 'Active' check (status in ('Active','Revoked','Invalid')),
  last_seen_at_utc timestamptz not null default now(),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  unique(provider,token_hash)
);
create index if not exists ix_messaging_push_account_active
  on messaging.push_registrations(account_id,product_code,status,last_seen_at_utc desc,id)
  where status='Active';

create table if not exists messaging.provider_pricing (
  id uuid primary key default gen_random_uuid(),
  provider varchar(40) not null,
  channel varchar(16) not null check (channel in ('SMS','Push')),
  country_code varchar(2),
  currency varchar(3) not null check (currency ~ '^[A-Z]{3}$'),
  cost_minor bigint not null check (cost_minor >= 0),
  effective_from_utc timestamptz not null,
  effective_to_utc timestamptz,
  status varchar(16) not null default 'Active' check (status in ('Active','Retired')),
  created_at_utc timestamptz not null default now(),
  check (effective_to_utc is null or effective_to_utc > effective_from_utc),
  unique(provider,channel,country_code,currency,effective_from_utc)
);

create table if not exists messaging.campaign_messages (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references marketing.campaigns(id) on delete cascade,
  channel varchar(16) not null check (channel in ('SMS','Push')),
  purpose varchar(32) not null default 'Promotional' check (purpose='Promotional'),
  title varchar(160),
  body varchar(2000) not null check (length(trim(body)) between 1 and 2000),
  content_hash char(64) not null check (content_hash ~ '^[0-9a-f]{64}$'),
  version bigint not null default 1 check (version>=1),
  status varchar(16) not null default 'Draft' check (status in ('Draft','Active','Retired')),
  created_by_account_id uuid not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  unique(campaign_id,channel,version)
);
create unique index if not exists uq_messaging_campaign_active_channel
  on messaging.campaign_messages(campaign_id,channel) where status='Active';

create table if not exists messaging.campaign_policies (
  policy_key varchar(96) primary key,
  value_json jsonb not null,
  value_type varchar(16) not null check (value_type in ('boolean','integer','json')),
  version bigint not null default 1 check (version>=1),
  status varchar(16) not null default 'Active' check (status in ('Active','Retired')),
  updated_by_account_id uuid not null,
  updated_at_utc timestamptz not null default now(),
  check (policy_key ~ '^[a-z][a-z0-9._-]{2,95}$')
);

create table if not exists messaging.campaign_executions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references marketing.campaigns(id) on delete restrict,
  audience_snapshot_id uuid not null references audience.segment_snapshots(id) on delete restrict,
  campaign_updated_at_utc timestamptz not null,
  status varchar(24) not null default 'Prepared'
    check (status in ('Prepared','ApprovalPending','Scheduled','Sending','Completed','Cancelled','Failed')),
  audience_count integer not null check (audience_count>=0),
  eligible_sms_count integer not null check (eligible_sms_count>=0),
  eligible_push_count integer not null check (eligible_push_count>=0),
  opted_out_sms_count integer not null check (opted_out_sms_count>=0),
  opted_out_push_count integer not null check (opted_out_push_count>=0),
  estimated_sms_cost_minor bigint,
  estimated_sms_cost_currency varchar(3),
  requires_second_confirmation boolean not null default false,
  confirmed_by_account_id uuid,
  confirmed_at_utc timestamptz,
  scheduled_at_utc timestamptz,
  created_by_account_id uuid not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  version bigint not null default 1 check(version>=1),
  check ((estimated_sms_cost_minor is null)=(estimated_sms_cost_currency is null)),
  check (estimated_sms_cost_minor is null or estimated_sms_cost_minor>=0),
  check (estimated_sms_cost_currency is null or estimated_sms_cost_currency ~ '^[A-Z]{3}$'),
  check ((confirmed_by_account_id is null)=(confirmed_at_utc is null))
);
create index if not exists ix_messaging_campaign_executions_status_schedule
  on messaging.campaign_executions(status,scheduled_at_utc,id);

create table if not exists messaging.delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  execution_id uuid not null references messaging.campaign_executions(id) on delete cascade,
  account_id uuid not null,
  channel varchar(16) not null check (channel in ('SMS','Push')),
  message_id uuid not null references messaging.campaign_messages(id) on delete restrict,
  status varchar(24) not null default 'Pending'
    check (status in ('Pending','InFlight','Delivered','Failed','Suppressed','Cancelled')),
  suppression_reason varchar(40) check (suppression_reason is null or suppression_reason in ('OptedOut','NoReachableAddress','InactiveAccount','Duplicate')),
  provider varchar(40),
  provider_reference_hash varchar(128),
  attempt_count integer not null default 0 check (attempt_count between 0 and 100),
  next_attempt_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (provider_reference_hash is null or provider_reference_hash ~ '^[0-9a-f]{64,128}$'),
  unique(execution_id,account_id,channel)
);
create index if not exists ix_messaging_delivery_jobs_claim
  on messaging.delivery_jobs(status,next_attempt_at_utc,created_at_utc,id)
  where status in ('Pending','Failed');

create table if not exists messaging.delivery_events (
  id uuid primary key default gen_random_uuid(),
  delivery_job_id uuid not null references messaging.delivery_jobs(id) on delete restrict,
  event_type varchar(24) not null check (event_type in ('Queued','Attempted','Delivered','Failed','Suppressed','Opened','Clicked','Converted')),
  provider varchar(40),
  provider_event_reference_hash varchar(128),
  reason_code varchar(80),
  occurred_at_utc timestamptz not null,
  recorded_at_utc timestamptz not null default now(),
  metadata_json jsonb not null default '{}'::jsonb,
  check (provider_event_reference_hash is null or provider_event_reference_hash ~ '^[0-9a-f]{64,128}$'),
  check (octet_length(metadata_json::text)<=4096)
);
create index if not exists ix_messaging_delivery_events_job_time
  on messaging.delivery_events(delivery_job_id,occurred_at_utc,id);

alter table messaging.push_registrations enable row level security;
alter table messaging.provider_pricing enable row level security;
alter table messaging.campaign_messages enable row level security;
alter table messaging.campaign_policies enable row level security;
alter table messaging.campaign_executions enable row level security;
alter table messaging.delivery_jobs enable row level security;
alter table messaging.delivery_events enable row level security;
alter table messaging.push_registrations force row level security;
alter table messaging.provider_pricing force row level security;
alter table messaging.campaign_messages force row level security;
alter table messaging.campaign_policies force row level security;
alter table messaging.campaign_executions force row level security;
alter table messaging.delivery_jobs force row level security;
alter table messaging.delivery_events force row level security;

revoke all on all tables in schema messaging from public;
do $$
begin
  if to_regrole('anon') is not null then execute 'revoke all on all tables in schema messaging from anon'; end if;
  if to_regrole('authenticated') is not null then execute 'revoke all on all tables in schema messaging from authenticated'; end if;
  if to_regrole('lifemate_edge_runtime') is not null then execute 'revoke all on all tables in schema messaging from lifemate_edge_runtime'; end if;
end $$;

create policy messaging_admin_read_push on messaging.push_registrations for select to lifemate_admin_runtime using(true);
create policy messaging_admin_rw_pricing on messaging.provider_pricing for all to lifemate_admin_runtime using(true) with check(true);
create policy messaging_admin_rw_messages on messaging.campaign_messages for all to lifemate_admin_runtime using(true) with check(true);
create policy messaging_admin_rw_policies on messaging.campaign_policies for all to lifemate_admin_runtime using(true) with check(true);
create policy messaging_admin_rw_executions on messaging.campaign_executions for all to lifemate_admin_runtime using(true) with check(true);
create policy messaging_admin_read_jobs on messaging.delivery_jobs for select to lifemate_admin_runtime using(true);
create policy messaging_admin_read_events on messaging.delivery_events for select to lifemate_admin_runtime using(true);
create policy messaging_worker_rw_push on messaging.push_registrations for select to lifemate_worker_runtime using(true);
create policy messaging_worker_rw_jobs on messaging.delivery_jobs for all to lifemate_worker_runtime using(true) with check(true);
create policy messaging_worker_insert_events on messaging.delivery_events for insert to lifemate_worker_runtime with check(true);

grant select on messaging.push_registrations to lifemate_admin_runtime,lifemate_worker_runtime;
grant select,insert,update on messaging.provider_pricing,messaging.campaign_messages,messaging.campaign_policies,messaging.campaign_executions to lifemate_admin_runtime;
grant select on messaging.delivery_jobs,messaging.delivery_events to lifemate_admin_runtime;
grant select,update on messaging.delivery_jobs to lifemate_worker_runtime;
grant insert on messaging.delivery_events to lifemate_worker_runtime;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('marketing.campaign.send','marketing','HIGH_RISK',true,'Prepare, confirm and schedule consent-aware outbound campaign executions')
on conflict (code) do update set description=excluded.description,updated_at_utc=now();
insert into admin.role_permissions(role_id,permission_code)
select r.id,'marketing.campaign.send' from admin.roles r where r.code in ('founder','super_admin','marketing')
on conflict do nothing;

insert into messaging.campaign_policies(policy_key,value_json,value_type,updated_by_account_id)
select 'second_confirmation.enabled','false'::jsonb,'boolean',m.account_id
from admin.members m join admin.member_roles mr on mr.account_id=m.account_id
join admin.roles r on r.id=mr.role_id
where r.code='founder' and m.status='Active'
order by m.created_at_utc
limit 1
on conflict(policy_key) do nothing;

create or replace function messaging.prepare_campaign_execution(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_snapshot_id uuid,
  p_campaign_updated_at_utc timestamptz,
  p_channels varchar[],
  p_sms_provider varchar,
  p_sms_currency varchar,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,marketing,audience,consent,identity,admin,pg_temp
as $$
declare
  v_campaign marketing.campaigns%rowtype;
  v_snapshot audience.segment_snapshots%rowtype;
  v_execution uuid;
  v_audience integer;
  v_eligible_sms integer:=0;
  v_eligible_push integer:=0;
  v_opt_sms integer:=0;
  v_opt_push integer:=0;
  v_cost bigint;
  v_currency varchar(3);
  v_second boolean:=false;
  v_account uuid;
  v_sms_allowed boolean;
  v_push_allowed boolean;
  v_sms_reachable boolean;
  v_push_reachable boolean;
  v_message_sms uuid;
  v_message_push uuid;
  v_channel varchar;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.send') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.');
  end if;
  if p_channels is null or cardinality(p_channels)<1 or cardinality(p_channels)>2
     or exists(select 1 from unnest(p_channels) c where c not in ('SMS','Push'))
     or cardinality(array(select distinct c from unnest(p_channels) c))<>cardinality(p_channels) then
    return jsonb_build_object('httpStatus',400,'code','campaign_channels_invalid','message','Campaign channels are invalid.');
  end if;

  select * into v_campaign from marketing.campaigns where id=p_campaign_id for share;
  if not found then return jsonb_build_object('httpStatus',404,'code','campaign_not_found','message','Campaign was not found.'); end if;
  if v_campaign.updated_at_utc<>p_campaign_updated_at_utc then
    return jsonb_build_object('httpStatus',409,'code','campaign_version_conflict','message','Campaign changed before execution preparation.');
  end if;
  if v_campaign.status not in ('Ready','Active') then
    return jsonb_build_object('httpStatus',409,'code','campaign_not_sendable','message','Campaign is not ready to send.');
  end if;

  select * into v_snapshot from audience.segment_snapshots where id=p_snapshot_id;
  if not found then return jsonb_build_object('httpStatus',404,'code','audience_snapshot_not_found','message','Audience snapshot was not found.'); end if;
  v_audience:=v_snapshot.member_count;
  if v_audience>100000 then
    return jsonb_build_object('httpStatus',409,'code','campaign_audience_too_large','message','Audience exceeds the approved execution ceiling.');
  end if;

  if 'SMS'=any(p_channels) then
    select id into v_message_sms from messaging.campaign_messages
    where campaign_id=p_campaign_id and channel='SMS' and status='Active';
    if v_message_sms is null then return jsonb_build_object('httpStatus',409,'code','campaign_sms_message_missing','message','Active SMS content is required.'); end if;
  end if;
  if 'Push'=any(p_channels) then
    select id into v_message_push from messaging.campaign_messages
    where campaign_id=p_campaign_id and channel='Push' and status='Active';
    if v_message_push is null then return jsonb_build_object('httpStatus',409,'code','campaign_push_message_missing','message','Active Push content is required.'); end if;
  end if;

  select coalesce((value_json #>> '{}')::boolean,false) into v_second
  from messaging.campaign_policies where policy_key='second_confirmation.enabled' and status='Active';
  v_second:=coalesce(v_second,false);

  insert into messaging.campaign_executions(
    campaign_id,audience_snapshot_id,campaign_updated_at_utc,status,audience_count,
    eligible_sms_count,eligible_push_count,opted_out_sms_count,opted_out_push_count,
    requires_second_confirmation,created_by_account_id
  ) values(
    p_campaign_id,p_snapshot_id,p_campaign_updated_at_utc,
    case when v_second then 'ApprovalPending' else 'Prepared' end,v_audience,0,0,0,0,v_second,p_actor_account_id
  ) returning id into v_execution;

  for v_account in select account_id from audience.segment_snapshot_members where snapshot_id=p_snapshot_id loop
    if 'SMS'=any(p_channels) then
      v_sms_allowed:=consent.account_allows_optional_purpose(v_account,'promotional_sms','GLOBAL');
      select exists(select 1 from identity.contact_points cp where cp.account_id=v_account and cp.kind='Phone' and cp.status='Verified' and cp.verified_at_utc is not null)
      into v_sms_reachable;
      if not v_sms_allowed then v_opt_sms:=v_opt_sms+1; end if;
      if v_sms_allowed and v_sms_reachable then
        v_eligible_sms:=v_eligible_sms+1;
        insert into messaging.delivery_jobs(execution_id,account_id,channel,message_id,status)
        values(v_execution,v_account,'SMS',v_message_sms,'Pending');
      else
        insert into messaging.delivery_jobs(execution_id,account_id,channel,message_id,status,suppression_reason)
        values(v_execution,v_account,'SMS',v_message_sms,'Suppressed',case when not v_sms_allowed then 'OptedOut' else 'NoReachableAddress' end);
      end if;
    end if;

    if 'Push'=any(p_channels) then
      v_push_allowed:=consent.account_allows_optional_purpose(v_account,'promotional_push','GLOBAL');
      select exists(select 1 from messaging.push_registrations pr where pr.account_id=v_account and pr.status='Active') into v_push_reachable;
      if not v_push_allowed then v_opt_push:=v_opt_push+1; end if;
      if v_push_allowed and v_push_reachable then
        v_eligible_push:=v_eligible_push+1;
        insert into messaging.delivery_jobs(execution_id,account_id,channel,message_id,status)
        values(v_execution,v_account,'Push',v_message_push,'Pending');
      else
        insert into messaging.delivery_jobs(execution_id,account_id,channel,message_id,status,suppression_reason)
        values(v_execution,v_account,'Push',v_message_push,'Suppressed',case when not v_push_allowed then 'OptedOut' else 'NoReachableAddress' end);
      end if;
    end if;
  end loop;

  if 'SMS'=any(p_channels) and p_sms_provider is not null and p_sms_currency is not null then
    select pp.cost_minor,pp.currency into v_cost,v_currency from messaging.provider_pricing pp
    where pp.provider=p_sms_provider and pp.channel='SMS' and pp.currency=p_sms_currency and pp.status='Active'
      and pp.effective_from_utc<=now() and (pp.effective_to_utc is null or pp.effective_to_utc>now())
    order by pp.effective_from_utc desc limit 1;
    if v_cost is not null then v_cost:=v_cost*v_eligible_sms; end if;
  end if;

  update messaging.campaign_executions set
    eligible_sms_count=v_eligible_sms,eligible_push_count=v_eligible_push,
    opted_out_sms_count=v_opt_sms,opted_out_push_count=v_opt_push,
    estimated_sms_cost_minor=v_cost,estimated_sms_cost_currency=v_currency,updated_at_utc=now()
  where id=v_execution;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'marketing.campaign.prepare','campaign_execution',v_execution::text,'Succeeded',p_correlation_id,false,
    jsonb_build_object('campaignId',p_campaign_id,'snapshotId',p_snapshot_id,'audienceCount',v_audience,'eligibleSms',v_eligible_sms,'eligiblePush',v_eligible_push,'requiresSecondConfirmation',v_second));

  return jsonb_build_object(
    'httpStatus',201,'code','ok','executionId',v_execution,
    'status',case when v_second then 'ApprovalPending' else 'Prepared' end,
    'audienceCount',v_audience,'eligibleSmsCount',v_eligible_sms,'eligiblePushCount',v_eligible_push,
    'optedOutSmsCount',v_opt_sms,'optedOutPushCount',v_opt_push,
    'estimatedSmsCostMinor',v_cost,'estimatedSmsCostCurrency',v_currency,
    'requiresSecondConfirmation',v_second
  );
end $$;

revoke all on function messaging.prepare_campaign_execution(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid) from public;
grant execute on function messaging.prepare_campaign_execution(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid) to lifemate_admin_runtime;

comment on table messaging.delivery_jobs is 'Privacy-minimized durable campaign work. Recipient contact/token plaintext is resolved only by provider workers and is never persisted here.';
comment on table messaging.delivery_events is 'Append-only truthful provider/delivery observations. Open/click/conversion facts may only be recorded when an instrumented source reports them.';
comment on table messaging.campaign_messages is 'Versioned outbound campaign content; operational logs must not copy message bodies.';

commit;
