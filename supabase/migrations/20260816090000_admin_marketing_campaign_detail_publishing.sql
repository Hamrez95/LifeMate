begin;

create schema if not exists marketing;

create table if not exists marketing.campaign_content (
  campaign_id uuid primary key references marketing.campaigns(id) on delete cascade,
  brief varchar(4000),
  audience_summary varchar(2000),
  publish_text varchar(4096),
  asset_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(asset_refs) = 'array'),
  content_revision integer not null default 1 check (content_revision >= 1),
  approval_state varchar(24) not null default 'Pending'
    check (approval_state in ('Pending','Approved','Revoked')),
  approved_revision integer,
  approved_by_admin_account_id uuid references admin.members(account_id) on delete set null,
  approved_at_utc timestamptz,
  updated_by_admin_account_id uuid not null references admin.members(account_id) on delete restrict,
  updated_at_utc timestamptz not null default now(),
  check (
    (approval_state = 'Approved' and approved_revision = content_revision and approved_at_utc is not null)
    or approval_state <> 'Approved'
  )
);

create table if not exists marketing.campaign_funnel_snapshots (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references marketing.campaigns(id) on delete cascade,
  source varchar(120) not null check (length(trim(source)) between 2 and 120),
  impressions bigint check (impressions is null or impressions >= 0),
  clicks bigint check (clicks is null or clicks >= 0),
  landing_views bigint check (landing_views is null or landing_views >= 0),
  conversions bigint check (conversions is null or conversions >= 0),
  captured_at_utc timestamptz not null,
  imported_at_utc timestamptz not null default now(),
  check (
    (clicks is null or impressions is null or clicks <= impressions)
    and (landing_views is null or clicks is null or landing_views <= clicks)
    and (conversions is null or landing_views is null or conversions <= landing_views)
  )
);
create index if not exists ix_marketing_campaign_funnel_latest
  on marketing.campaign_funnel_snapshots(campaign_id, captured_at_utc desc, id desc);

create table if not exists marketing.campaign_publish_executions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references marketing.campaigns(id) on delete cascade,
  provider_code varchar(64) not null references marketing.channel_connections(provider_code) on delete restrict,
  content_revision integer not null check (content_revision >= 1),
  status varchar(24) not null default 'Queued'
    check (status in ('Queued','Processing','Published','Failed','OutcomeUnknown')),
  requested_by_admin_account_id uuid not null references admin.members(account_id) on delete restrict,
  requested_at_utc timestamptz not null default now(),
  started_at_utc timestamptz,
  completed_at_utc timestamptz,
  provider_post_ref varchar(300),
  failure_code varchar(80),
  request_id varchar(180) not null,
  correlation_id uuid not null,
  check (provider_post_ref is null or length(provider_post_ref) between 1 and 300),
  check (failure_code is null or failure_code ~ '^[A-Za-z0-9:_-]{1,80}$')
);
create index if not exists ix_marketing_campaign_publish_history
  on marketing.campaign_publish_executions(campaign_id, requested_at_utc desc, id desc);
create unique index if not exists uq_marketing_campaign_publish_revision_guard
  on marketing.campaign_publish_executions(campaign_id, provider_code, content_revision)
  where status in ('Queued','Processing','Published','OutcomeUnknown');

create table if not exists marketing.campaign_publish_execution_events (
  id uuid primary key default gen_random_uuid(),
  execution_id uuid not null references marketing.campaign_publish_executions(id) on delete cascade,
  event_type varchar(24) not null
    check (event_type in ('Queued','Processing','Published','Failed','OutcomeUnknown')),
  code varchar(80),
  occurred_at_utc timestamptz not null default now(),
  check (code is null or code ~ '^[A-Za-z0-9:_-]{1,80}$')
);
create index if not exists ix_marketing_publish_execution_events
  on marketing.campaign_publish_execution_events(execution_id, occurred_at_utc, id);

revoke all on marketing.campaign_content from public;
revoke all on marketing.campaign_funnel_snapshots from public;
revoke all on marketing.campaign_publish_executions from public;
revoke all on marketing.campaign_publish_execution_events from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if to_regrole(v_role) is not null then
      execute format('revoke all on marketing.campaign_content from %I', v_role);
      execute format('revoke all on marketing.campaign_funnel_snapshots from %I', v_role);
      execute format('revoke all on marketing.campaign_publish_executions from %I', v_role);
      execute format('revoke all on marketing.campaign_publish_execution_events from %I', v_role);
    end if;
  end loop;
end
$$;

grant usage on schema marketing to lifemate_admin_runtime;
grant select on marketing.campaign_content to lifemate_admin_runtime;
grant select on marketing.campaign_funnel_snapshots to lifemate_admin_runtime;
grant select on marketing.campaign_publish_executions to lifemate_admin_runtime;
grant select on marketing.campaign_publish_execution_events to lifemate_admin_runtime;

create or replace function admin.update_marketing_campaign_content(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_brief varchar,
  p_audience_summary varchar,
  p_publish_text varchar,
  p_asset_refs jsonb,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = admin, marketing, pg_temp
as $$
declare
  v_operation varchar := 'marketing.campaign.content:' || p_campaign_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_current marketing.campaign_content%rowtype;
  v_revision integer;
  v_changed boolean;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'marketing.campaign.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if not exists(select 1 from marketing.campaigns where id=p_campaign_id) then
    return jsonb_build_object('httpStatus',404,'code','marketing_campaign_not_found','message','Campaign was not found.','replayed',false);
  end if;
  if p_brief is not null and length(trim(p_brief)) > 4000 then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_brief_invalid','message','Campaign brief is invalid.','replayed',false);
  end if;
  if p_audience_summary is not null and length(trim(p_audience_summary)) > 2000 then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_audience_invalid','message','Campaign audience summary is invalid.','replayed',false);
  end if;
  if p_publish_text is not null and (length(trim(p_publish_text)) < 1 or length(trim(p_publish_text)) > 4096) then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_publish_text_invalid','message','Publish text is invalid.','replayed',false);
  end if;
  if p_asset_refs is null or jsonb_typeof(p_asset_refs) <> 'array' or jsonb_array_length(p_asset_refs) > 20
     or exists(
       select 1 from jsonb_array_elements(p_asset_refs) value
       where jsonb_typeof(value) <> 'string'
          or length(trim(value #>> '{}')) < 1
          or length(trim(value #>> '{}')) > 500
     ) then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_assets_invalid','message','Campaign asset references are invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key
   for update;
  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  select * into v_current from marketing.campaign_content where campaign_id=p_campaign_id for update;
  if found then
    v_changed := v_current.brief is distinct from nullif(trim(coalesce(p_brief,'')),'')
      or v_current.audience_summary is distinct from nullif(trim(coalesce(p_audience_summary,'')),'')
      or v_current.publish_text is distinct from nullif(trim(coalesce(p_publish_text,'')),'')
      or v_current.asset_refs is distinct from p_asset_refs;
    v_revision := v_current.content_revision + case when v_changed then 1 else 0 end;
    update marketing.campaign_content set
      brief=nullif(trim(coalesce(p_brief,'')),''),
      audience_summary=nullif(trim(coalesce(p_audience_summary,'')),''),
      publish_text=nullif(trim(coalesce(p_publish_text,'')),''),
      asset_refs=p_asset_refs,
      content_revision=v_revision,
      approval_state=case when v_changed then 'Pending' else approval_state end,
      approved_revision=case when v_changed then null else approved_revision end,
      approved_by_admin_account_id=case when v_changed then null else approved_by_admin_account_id end,
      approved_at_utc=case when v_changed then null else approved_at_utc end,
      updated_by_admin_account_id=p_actor_account_id,
      updated_at_utc=now()
    where campaign_id=p_campaign_id;
  else
    v_changed := true;
    v_revision := 1;
    insert into marketing.campaign_content(
      campaign_id,brief,audience_summary,publish_text,asset_refs,content_revision,
      approval_state,updated_by_admin_account_id
    ) values(
      p_campaign_id,nullif(trim(coalesce(p_brief,'')),''),nullif(trim(coalesce(p_audience_summary,'')),''),
      nullif(trim(coalesce(p_publish_text,'')),''),p_asset_refs,1,'Pending',p_actor_account_id
    );
  end if;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'marketing.campaign.content.update','marketing_campaign',p_campaign_id::text,'Succeeded',trim(p_reason),
    p_correlation_id,p_idempotency_key,false,jsonb_build_object('contentRevision',v_revision,'approvalState',case when v_changed then 'Pending' else coalesce(v_current.approval_state,'Pending') end,'assetCount',jsonb_array_length(p_asset_refs))
  );

  v_response := jsonb_build_object('httpStatus',200,'code','ok','campaignId',p_campaign_id,'contentRevision',v_revision,'approvalState',case when v_changed then 'Pending' else coalesce(v_current.approval_state,'Pending') end,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.set_marketing_campaign_approval(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_approved boolean,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = admin, marketing, pg_temp
as $$
declare
  v_operation varchar := 'marketing.campaign.approval:' || p_campaign_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_target varchar := case when p_approved then 'Approved' else 'Revoked' end;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  select * into v_content from marketing.campaign_content where campaign_id=p_campaign_id for update;
  if not found then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_content_missing','message','Campaign content must be prepared before approval.','replayed',false);
  elsif p_approved and (v_content.publish_text is null or length(trim(v_content.publish_text))=0) then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_publish_text_missing','message','Publish text is required before approval.','replayed',false);
  elsif p_approved and not exists(select 1 from marketing.campaigns where id=p_campaign_id and channel_code is not null) then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_channel_missing','message','A campaign channel is required before approval.','replayed',false);
  else
    update marketing.campaign_content set
      approval_state=v_target,
      approved_revision=case when p_approved then content_revision else null end,
      approved_by_admin_account_id=case when p_approved then p_actor_account_id else null end,
      approved_at_utc=case when p_approved then now() else null end,
      updated_by_admin_account_id=p_actor_account_id,
      updated_at_utc=now()
    where campaign_id=p_campaign_id;
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,'marketing.campaign.approval','marketing_campaign',p_campaign_id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,jsonb_build_object('approvalState',v_target,'contentRevision',v_content.content_revision));
    v_response := jsonb_build_object('httpStatus',200,'code','ok','campaignId',p_campaign_id,'approvalState',v_target,'contentRevision',v_content.content_revision,'replayed',false);
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,'marketing.campaign.approval','marketing_campaign',p_campaign_id::text,'Denied',coalesce(v_response->>'message','Campaign approval denied'),p_correlation_id,p_idempotency_key,false,jsonb_build_object('code',v_response->>'code'));
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.request_marketing_campaign_publish(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = admin, marketing, integration, pg_temp
as $$
declare
  v_operation varchar := 'marketing.campaign.publish:' || p_campaign_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_execution_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.social.publish') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required high-risk marketing permission is not granted.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  select * into v_campaign from marketing.campaigns where id=p_campaign_id for update;
  select * into v_content from marketing.campaign_content where campaign_id=p_campaign_id for update;

  if v_campaign.id is null then
    v_response := jsonb_build_object('httpStatus',404,'code','marketing_campaign_not_found','message','Campaign was not found.','replayed',false);
  elsif v_campaign.status not in ('Ready','Active') then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_not_publishable','message','Campaign lifecycle is not publishable.','replayed',false);
  elsif v_content.campaign_id is null or v_content.approval_state<>'Approved' or v_content.approved_revision is distinct from v_content.content_revision then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_approval_required','message','The current content revision requires human approval.','replayed',false);
  elsif v_campaign.channel_code is null then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_channel_missing','message','Campaign channel is not configured.','replayed',false);
  elsif not exists(select 1 from marketing.channel_connections c where c.provider_code=v_campaign.channel_code and c.operator_status='Enabled') then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_channel_disabled','message','Campaign channel is disabled or unavailable.','replayed',false);
  elsif not admin.marketing_channel_credential_available(v_campaign.channel_code) then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_channel_setup_required','message','Campaign channel credential is not available.','replayed',false);
  elsif exists(
    select 1 from marketing.campaign_publish_executions e
    where e.campaign_id=p_campaign_id and e.provider_code=v_campaign.channel_code
      and e.content_revision=v_content.content_revision
      and e.status in ('Queued','Processing','Published','OutcomeUnknown')
  ) then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_publish_duplicate_guard','message','This approved content revision already has a protected publish execution.','replayed',false);
  else
    v_execution_id := gen_random_uuid();
    insert into marketing.campaign_publish_executions(
      id,campaign_id,provider_code,content_revision,status,requested_by_admin_account_id,request_id,correlation_id
    ) values(v_execution_id,p_campaign_id,v_campaign.channel_code,v_content.content_revision,'Queued',p_actor_account_id,p_idempotency_key,p_correlation_id);
    insert into marketing.campaign_publish_execution_events(execution_id,event_type)
    values(v_execution_id,'Queued');
    insert into integration.outbox_messages(
      aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc
    ) values(
      'marketing_campaign',p_campaign_id,'marketing.campaign_publish_requested',
      'marketing-publish:'||v_execution_id::text,
      jsonb_build_object('executionId',v_execution_id),'Pending',now()
    );
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,'marketing.campaign.publish.request','marketing_campaign',p_campaign_id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,jsonb_build_object('executionId',v_execution_id,'providerCode',v_campaign.channel_code,'contentRevision',v_content.content_revision,'providerConnectivity','NotVerified'));
    v_response := jsonb_build_object('httpStatus',202,'code','ok','campaignId',p_campaign_id,'executionId',v_execution_id,'publishStatus','Queued','providerConnectivity','NotVerified','replayed',false);
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,'marketing.campaign.publish.request','marketing_campaign',p_campaign_id::text,'Denied',coalesce(v_response->>'message','Campaign publish request denied'),p_correlation_id,p_idempotency_key,false,jsonb_build_object('code',v_response->>'code'));
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function marketing.claim_campaign_publish_execution(p_execution_id uuid)
returns table(
  execution_id uuid,
  campaign_id uuid,
  provider_code varchar,
  publish_text varchar,
  asset_refs jsonb,
  credential_secret_name varchar
)
language plpgsql
security definer
set search_path = marketing, admin, pg_temp
as $$
declare
  v_execution marketing.campaign_publish_executions%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_secret_name varchar;
  v_failure varchar;
begin
  select * into v_execution from marketing.campaign_publish_executions where id=p_execution_id for update;
  if not found or v_execution.status <> 'Queued' then return; end if;
  select * into v_campaign from marketing.campaigns where id=v_execution.campaign_id;
  select * into v_content from marketing.campaign_content where campaign_id=v_execution.campaign_id;
  select credential_secret_name into v_secret_name from marketing.channel_connections
   where provider_code=v_execution.provider_code and operator_status='Enabled';

  if v_campaign.status not in ('Ready','Active') then v_failure := 'campaign_not_publishable';
  elsif v_content.approval_state <> 'Approved' or v_content.approved_revision is distinct from v_execution.content_revision or v_content.content_revision is distinct from v_execution.content_revision then v_failure := 'approval_changed';
  elsif v_secret_name is null or not admin.marketing_channel_credential_available(v_execution.provider_code) then v_failure := 'provider_not_configured';
  end if;

  if v_failure is not null then
    update marketing.campaign_publish_executions set status='Failed',completed_at_utc=now(),failure_code=v_failure where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type,code) values(p_execution_id,'Failed',v_failure);
    return;
  end if;

  update marketing.campaign_publish_executions set status='Processing',started_at_utc=now(),failure_code=null where id=p_execution_id;
  insert into marketing.campaign_publish_execution_events(execution_id,event_type) values(p_execution_id,'Processing');
  return query select v_execution.id,v_execution.campaign_id,v_execution.provider_code,v_content.publish_text,v_content.asset_refs,v_secret_name;
end
$$;

create or replace function marketing.resolve_marketing_secret_for_worker(p_secret_name varchar)
returns text
language plpgsql
security definer
set search_path = marketing, pg_temp
as $$
declare v_secret text;
begin
  if p_secret_name is null or p_secret_name !~ '^lifemate_marketing_[a-z0-9_:-]+_token$' or to_regnamespace('vault') is null then
    return null;
  end if;
  begin
    execute 'select decrypted_secret from vault.decrypted_secrets where name=$1 limit 1' into v_secret using p_secret_name;
  exception when others then
    return null;
  end;
  return nullif(v_secret,'');
end
$$;

create or replace function marketing.complete_campaign_publish_execution(p_execution_id uuid,p_provider_post_ref varchar)
returns boolean
language plpgsql
security definer
set search_path = marketing, pg_temp
as $$
begin
  if p_provider_post_ref is null or length(trim(p_provider_post_ref))<1 or length(trim(p_provider_post_ref))>300 then return false; end if;
  update marketing.campaign_publish_executions set status='Published',provider_post_ref=trim(p_provider_post_ref),completed_at_utc=now(),failure_code=null
   where id=p_execution_id and status='Processing';
  if not found then return false; end if;
  insert into marketing.campaign_publish_execution_events(execution_id,event_type) values(p_execution_id,'Published');
  return true;
end
$$;

create or replace function marketing.fail_campaign_publish_execution(p_execution_id uuid,p_failure_code varchar,p_outcome_unknown boolean default false)
returns boolean
language plpgsql
security definer
set search_path = marketing, pg_temp
as $$
declare v_status varchar := case when p_outcome_unknown then 'OutcomeUnknown' else 'Failed' end;
begin
  if p_failure_code is null or p_failure_code !~ '^[A-Za-z0-9:_-]{1,80}$' then return false; end if;
  update marketing.campaign_publish_executions set status=v_status,failure_code=p_failure_code,completed_at_utc=now()
   where id=p_execution_id and status='Processing';
  if not found then return false; end if;
  insert into marketing.campaign_publish_execution_events(execution_id,event_type,code) values(p_execution_id,v_status,p_failure_code);
  return true;
end
$$;

revoke all on function admin.update_marketing_campaign_content(uuid,uuid,varchar,varchar,varchar,jsonb,varchar,uuid,varchar,varchar) from public;
revoke all on function admin.set_marketing_campaign_approval(uuid,uuid,boolean,varchar,uuid,varchar,varchar) from public;
revoke all on function admin.request_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) from public;
revoke all on function marketing.claim_campaign_publish_execution(uuid) from public;
revoke all on function marketing.resolve_marketing_secret_for_worker(varchar) from public;
revoke all on function marketing.complete_campaign_publish_execution(uuid,varchar) from public;
revoke all on function marketing.fail_campaign_publish_execution(uuid,varchar,boolean) from public;

grant execute on function admin.update_marketing_campaign_content(uuid,uuid,varchar,varchar,varchar,jsonb,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.set_marketing_campaign_approval(uuid,uuid,boolean,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.request_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

grant usage on schema marketing to lifemate_worker_runtime;
grant execute on function marketing.claim_campaign_publish_execution(uuid) to lifemate_worker_runtime;
grant execute on function marketing.resolve_marketing_secret_for_worker(varchar) to lifemate_worker_runtime;
grant execute on function marketing.complete_campaign_publish_execution(uuid,varchar) to lifemate_worker_runtime;
grant execute on function marketing.fail_campaign_publish_execution(uuid,varchar,boolean) to lifemate_worker_runtime;

comment on table marketing.campaign_content is
  'Human-authored campaign brief/content. Editing the current revision invalidates approval.';
comment on table marketing.campaign_funnel_snapshots is
  'Privacy-minimized aggregate funnel snapshots. Missing snapshots must be rendered as unavailable, never fabricated.';
comment on table marketing.campaign_publish_executions is
  'Publishing lifecycle is separate from campaign lifecycle. OutcomeUnknown is fail-closed to prevent duplicate external side effects.';
comment on function marketing.resolve_marketing_secret_for_worker(varchar) is
  'Worker-only Vault resolver. Decrypted provider secrets are never exposed through Admin API projections.';

commit;
