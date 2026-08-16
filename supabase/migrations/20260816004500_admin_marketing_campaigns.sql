begin;

create schema if not exists marketing;

create table if not exists marketing.campaigns (
  id uuid primary key default gen_random_uuid(),
  name varchar(160) not null check (length(trim(name)) between 2 and 160),
  objective varchar(500),
  product_code varchar(64),
  channel_code varchar(64),
  status varchar(24) not null default 'Draft'
    check (status in ('Draft','Ready','Active','Paused','Completed','Cancelled')),
  starts_at_utc timestamptz,
  ends_at_utc timestamptz,
  owner_admin_account_id uuid references admin.members(account_id) on delete set null,
  created_by_admin_account_id uuid not null references admin.members(account_id) on delete restrict,
  updated_by_admin_account_id uuid not null references admin.members(account_id) on delete restrict,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (product_code is null or product_code ~ '^[a-z0-9][a-z0-9_.:-]{0,63}$'),
  check (channel_code is null or channel_code ~ '^[a-z0-9][a-z0-9_.:-]{0,63}$'),
  check (ends_at_utc is null or starts_at_utc is null or ends_at_utc >= starts_at_utc)
);

create index if not exists ix_marketing_campaigns_status_updated
  on marketing.campaigns(status, updated_at_utc desc, id desc);
create index if not exists ix_marketing_campaigns_product_status_updated
  on marketing.campaigns(product_code, status, updated_at_utc desc, id desc)
  where product_code is not null;
create index if not exists ix_marketing_campaigns_channel_status_updated
  on marketing.campaigns(channel_code, status, updated_at_utc desc, id desc)
  where channel_code is not null;
create index if not exists ix_marketing_campaigns_owner_status_updated
  on marketing.campaigns(owner_admin_account_id, status, updated_at_utc desc, id desc)
  where owner_admin_account_id is not null;

create table if not exists marketing.campaign_events (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references marketing.campaigns(id) on delete cascade,
  event_type varchar(40) not null
    check (event_type in ('Created','Updated','StatusChanged')),
  from_status varchar(24),
  to_status varchar(24) not null
    check (to_status in ('Draft','Ready','Active','Paused','Completed','Cancelled')),
  reason varchar(1000),
  actor_admin_account_id uuid not null references admin.members(account_id) on delete restrict,
  recorded_at_utc timestamptz not null default now(),
  check (from_status is null or from_status in ('Draft','Ready','Active','Paused','Completed','Cancelled'))
);

create index if not exists ix_marketing_campaign_events_campaign_time
  on marketing.campaign_events(campaign_id, recorded_at_utc desc, id desc);

create or replace view admin.marketing_campaigns_v1
with (security_invoker = true)
as
select
  c.id as campaign_id,
  c.name,
  c.objective,
  c.product_code,
  c.channel_code,
  c.status,
  c.starts_at_utc,
  c.ends_at_utc,
  c.owner_admin_account_id,
  c.created_at_utc,
  c.updated_at_utc
from marketing.campaigns c;

revoke all on schema marketing from public;
revoke all on marketing.campaigns from public;
revoke all on marketing.campaign_events from public;
revoke all on admin.marketing_campaigns_v1 from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if to_regrole(v_role) is not null then
      execute format('revoke all on schema marketing from %I', v_role);
      execute format('revoke all on marketing.campaigns from %I', v_role);
      execute format('revoke all on marketing.campaign_events from %I', v_role);
      execute format('revoke all on admin.marketing_campaigns_v1 from %I', v_role);
    end if;
  end loop;
end
$$;

grant usage on schema marketing to lifemate_admin_runtime;
grant select on marketing.campaigns to lifemate_admin_runtime;
grant select on marketing.campaign_events to lifemate_admin_runtime;
grant select on admin.marketing_campaigns_v1 to lifemate_admin_runtime;

create or replace function admin.create_marketing_campaign(
  p_actor_account_id uuid,
  p_name varchar,
  p_objective varchar,
  p_product_code varchar,
  p_channel_code varchar,
  p_owner_admin_account_id uuid,
  p_starts_at_utc timestamptz,
  p_ends_at_utc timestamptz,
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
  v_operation constant varchar := 'marketing.campaign.create';
  v_existing admin.idempotency_keys%rowtype;
  v_campaign_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'marketing.campaign.write') then
    return jsonb_build_object('httpStatus', 403, 'code', 'permission_denied', 'message', 'The required permission is not granted.', 'replayed', false);
  end if;
  if p_name is null or length(trim(p_name)) < 2 or length(trim(p_name)) > 160 then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_name_invalid', 'message', 'Campaign name is invalid.', 'replayed', false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_reason_invalid', 'message', 'A reason between 10 and 1000 characters is required.', 'replayed', false);
  end if;
  if p_objective is not null and length(trim(p_objective)) > 500 then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_objective_invalid', 'message', 'Campaign objective is invalid.', 'replayed', false);
  end if;
  if p_product_code is not null and p_product_code !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$' then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_product_invalid', 'message', 'Campaign product code is invalid.', 'replayed', false);
  end if;
  if p_channel_code is not null and p_channel_code !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$' then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_channel_invalid', 'message', 'Campaign channel code is invalid.', 'replayed', false);
  end if;
  if p_starts_at_utc is not null and p_ends_at_utc is not null and p_ends_at_utc < p_starts_at_utc then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_window_invalid', 'message', 'Campaign time window is invalid.', 'replayed', false);
  end if;
  if p_owner_admin_account_id is not null and not exists(
    select 1 from admin.members where account_id = p_owner_admin_account_id and status = 'Active'
  ) then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_owner_invalid', 'message', 'Campaign owner is not an active admin member.', 'replayed', false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus', 400, 'code', 'idempotency_invalid', 'message', 'Idempotency metadata is invalid.', 'replayed', false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key, 0));
  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_conflict', 'message', 'This Idempotency-Key was already used for a different request.', 'replayed', false);
    end if;
    if v_existing.status = 'Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed', true);
    end if;
    return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_in_progress', 'message', 'The matching request is still being processed.', 'replayed', false);
  end if;

  insert into admin.idempotency_keys(actor_account_id, operation, idempotency_key, request_hash, status)
  values (p_actor_account_id, v_operation, p_idempotency_key, p_request_hash, 'Processing');

  insert into marketing.campaigns(
    name, objective, product_code, channel_code, status, starts_at_utc, ends_at_utc,
    owner_admin_account_id, created_by_admin_account_id, updated_by_admin_account_id
  ) values (
    trim(p_name), nullif(trim(coalesce(p_objective, '')), ''), p_product_code, p_channel_code,
    'Draft', p_starts_at_utc, p_ends_at_utc, p_owner_admin_account_id,
    p_actor_account_id, p_actor_account_id
  ) returning id into v_campaign_id;

  insert into marketing.campaign_events(
    campaign_id, event_type, from_status, to_status, reason, actor_admin_account_id
  ) values (
    v_campaign_id, 'Created', null, 'Draft', trim(p_reason), p_actor_account_id
  );

  insert into admin.audit_events(
    actor_account_id, action, resource_type, resource_id, result, reason,
    correlation_id, request_id, elevated_access, metadata_json
  ) values (
    p_actor_account_id, 'marketing.campaign.create', 'marketing_campaign', v_campaign_id::text,
    'Succeeded', trim(p_reason), p_correlation_id, p_idempotency_key, false,
    jsonb_build_object('status', 'Draft', 'productCode', p_product_code, 'channelCode', p_channel_code)
  );

  v_response := jsonb_build_object(
    'httpStatus', 201,
    'code', 'ok',
    'campaignId', v_campaign_id,
    'status', 'Draft',
    'replayed', false
  );

  update admin.idempotency_keys
  set status = 'Completed', response_status = 201, response_json = v_response, updated_at_utc = now()
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key;

  return v_response;
end
$$;

create or replace function admin.update_marketing_campaign(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_name varchar,
  p_objective varchar,
  p_product_code varchar,
  p_channel_code varchar,
  p_owner_admin_account_id uuid,
  p_starts_at_utc timestamptz,
  p_ends_at_utc timestamptz,
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
  v_operation varchar := 'marketing.campaign.update:' || p_campaign_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_current marketing.campaigns%rowtype;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'marketing.campaign.write') then
    return jsonb_build_object('httpStatus', 403, 'code', 'permission_denied', 'message', 'The required permission is not granted.', 'replayed', false);
  end if;
  if p_name is null or length(trim(p_name)) < 2 or length(trim(p_name)) > 160 then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_name_invalid', 'message', 'Campaign name is invalid.', 'replayed', false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_reason_invalid', 'message', 'A reason between 10 and 1000 characters is required.', 'replayed', false);
  end if;
  if p_objective is not null and length(trim(p_objective)) > 500 then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_objective_invalid', 'message', 'Campaign objective is invalid.', 'replayed', false);
  end if;
  if p_product_code is not null and p_product_code !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$' then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_product_invalid', 'message', 'Campaign product code is invalid.', 'replayed', false);
  end if;
  if p_channel_code is not null and p_channel_code !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$' then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_channel_invalid', 'message', 'Campaign channel code is invalid.', 'replayed', false);
  end if;
  if p_starts_at_utc is not null and p_ends_at_utc is not null and p_ends_at_utc < p_starts_at_utc then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_window_invalid', 'message', 'Campaign time window is invalid.', 'replayed', false);
  end if;
  if p_owner_admin_account_id is not null and not exists(
    select 1 from admin.members where account_id = p_owner_admin_account_id and status = 'Active'
  ) then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_owner_invalid', 'message', 'Campaign owner is not an active admin member.', 'replayed', false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus', 400, 'code', 'idempotency_invalid', 'message', 'Idempotency metadata is invalid.', 'replayed', false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key, 0));
  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_conflict', 'message', 'This Idempotency-Key was already used for a different request.', 'replayed', false);
    end if;
    if v_existing.status = 'Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed', true);
    end if;
    return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_in_progress', 'message', 'The matching request is still being processed.', 'replayed', false);
  end if;

  insert into admin.idempotency_keys(actor_account_id, operation, idempotency_key, request_hash, status)
  values (p_actor_account_id, v_operation, p_idempotency_key, p_request_hash, 'Processing');

  select * into v_current
  from marketing.campaigns
  where id = p_campaign_id
  for update;

  if not found then
    v_response := jsonb_build_object('httpStatus', 404, 'code', 'marketing_campaign_not_found', 'message', 'Campaign was not found.', 'replayed', false);
  elsif v_current.status not in ('Draft','Ready','Paused') then
    v_response := jsonb_build_object('httpStatus', 409, 'code', 'marketing_campaign_not_editable', 'message', 'Campaign must be Draft, Ready or Paused before its planning fields can be edited.', 'replayed', false);
  else
    update marketing.campaigns
    set name = trim(p_name),
        objective = nullif(trim(coalesce(p_objective, '')), ''),
        product_code = p_product_code,
        channel_code = p_channel_code,
        owner_admin_account_id = p_owner_admin_account_id,
        starts_at_utc = p_starts_at_utc,
        ends_at_utc = p_ends_at_utc,
        updated_by_admin_account_id = p_actor_account_id,
        updated_at_utc = now()
    where id = p_campaign_id;

    insert into marketing.campaign_events(
      campaign_id, event_type, from_status, to_status, reason, actor_admin_account_id
    ) values (
      p_campaign_id, 'Updated', v_current.status, v_current.status, trim(p_reason), p_actor_account_id
    );

    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id, 'marketing.campaign.update', 'marketing_campaign', p_campaign_id::text,
      'Succeeded', trim(p_reason), p_correlation_id, p_idempotency_key, false,
      jsonb_build_object('status', v_current.status, 'productCode', p_product_code, 'channelCode', p_channel_code)
    );

    v_response := jsonb_build_object(
      'httpStatus', 200,
      'code', 'ok',
      'campaignId', p_campaign_id,
      'status', v_current.status,
      'replayed', false
    );
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id, 'marketing.campaign.update', 'marketing_campaign', p_campaign_id::text,
      'Denied', coalesce(v_response->>'message', 'Campaign update denied'), p_correlation_id,
      p_idempotency_key, false, jsonb_build_object('code', v_response->>'code')
    );
  end if;

  update admin.idempotency_keys
  set status = 'Completed',
      response_status = (v_response->>'httpStatus')::integer,
      response_json = v_response,
      updated_at_utc = now()
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key;

  return v_response;
end
$$;

create or replace function admin.set_marketing_campaign_status(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_target_status varchar,
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
  v_operation varchar := 'marketing.campaign.status:' || p_campaign_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_current marketing.campaigns%rowtype;
  v_allowed boolean := false;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'marketing.campaign.write') then
    return jsonb_build_object('httpStatus', 403, 'code', 'permission_denied', 'message', 'The required permission is not granted.', 'replayed', false);
  end if;
  if p_target_status not in ('Draft','Ready','Active','Paused','Completed','Cancelled') then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_status_invalid', 'message', 'Target campaign status is invalid.', 'replayed', false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_campaign_reason_invalid', 'message', 'A reason between 10 and 1000 characters is required.', 'replayed', false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus', 400, 'code', 'idempotency_invalid', 'message', 'Idempotency metadata is invalid.', 'replayed', false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key, 0));
  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_conflict', 'message', 'This Idempotency-Key was already used for a different request.', 'replayed', false);
    end if;
    if v_existing.status = 'Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed', true);
    end if;
    return jsonb_build_object('httpStatus', 409, 'code', 'idempotency_in_progress', 'message', 'The matching request is still being processed.', 'replayed', false);
  end if;

  insert into admin.idempotency_keys(actor_account_id, operation, idempotency_key, request_hash, status)
  values (p_actor_account_id, v_operation, p_idempotency_key, p_request_hash, 'Processing');

  select * into v_current
  from marketing.campaigns
  where id = p_campaign_id
  for update;

  if not found then
    v_response := jsonb_build_object('httpStatus', 404, 'code', 'marketing_campaign_not_found', 'message', 'Campaign was not found.', 'replayed', false);
  elsif v_current.status = p_target_status then
    v_response := jsonb_build_object(
      'httpStatus', 200, 'code', 'ok', 'campaignId', p_campaign_id,
      'previousStatus', v_current.status, 'status', v_current.status,
      'noop', true, 'replayed', false
    );
  else
    v_allowed :=
      (v_current.status = 'Draft' and p_target_status in ('Ready','Cancelled'))
      or (v_current.status = 'Ready' and p_target_status in ('Draft','Active','Cancelled'))
      or (v_current.status = 'Active' and p_target_status in ('Paused','Completed','Cancelled'))
      or (v_current.status = 'Paused' and p_target_status in ('Active','Completed','Cancelled'));

    if not v_allowed then
      v_response := jsonb_build_object('httpStatus', 409, 'code', 'marketing_campaign_transition_invalid', 'message', 'Campaign status transition is not allowed.', 'replayed', false);
    else
      update marketing.campaigns
      set status = p_target_status,
          updated_by_admin_account_id = p_actor_account_id,
          updated_at_utc = now()
      where id = p_campaign_id;

      insert into marketing.campaign_events(
        campaign_id, event_type, from_status, to_status, reason, actor_admin_account_id
      ) values (
        p_campaign_id, 'StatusChanged', v_current.status, p_target_status,
        trim(p_reason), p_actor_account_id
      );

      insert into admin.audit_events(
        actor_account_id, action, resource_type, resource_id, result, reason,
        correlation_id, request_id, elevated_access, metadata_json
      ) values (
        p_actor_account_id, 'marketing.campaign.status', 'marketing_campaign', p_campaign_id::text,
        'Succeeded', trim(p_reason), p_correlation_id, p_idempotency_key, false,
        jsonb_build_object('fromStatus', v_current.status, 'toStatus', p_target_status)
      );

      v_response := jsonb_build_object(
        'httpStatus', 200, 'code', 'ok', 'campaignId', p_campaign_id,
        'previousStatus', v_current.status, 'status', p_target_status,
        'noop', false, 'replayed', false
      );
    end if;
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id, 'marketing.campaign.status', 'marketing_campaign', p_campaign_id::text,
      'Denied', coalesce(v_response->>'message', 'Campaign status change denied'), p_correlation_id,
      p_idempotency_key, false,
      jsonb_build_object('code', v_response->>'code', 'targetStatus', p_target_status)
    );
  end if;

  update admin.idempotency_keys
  set status = 'Completed',
      response_status = (v_response->>'httpStatus')::integer,
      response_json = v_response,
      updated_at_utc = now()
  where actor_account_id = p_actor_account_id
    and operation = v_operation
    and idempotency_key = p_idempotency_key;

  return v_response;
end
$$;

revoke all on function admin.create_marketing_campaign(
  uuid, varchar, varchar, varchar, varchar, uuid, timestamptz, timestamptz,
  varchar, uuid, varchar, varchar
) from public;
revoke all on function admin.update_marketing_campaign(
  uuid, uuid, varchar, varchar, varchar, varchar, uuid, timestamptz, timestamptz,
  varchar, uuid, varchar, varchar
) from public;
revoke all on function admin.set_marketing_campaign_status(
  uuid, uuid, varchar, varchar, uuid, varchar, varchar
) from public;

grant execute on function admin.create_marketing_campaign(
  uuid, varchar, varchar, varchar, varchar, uuid, timestamptz, timestamptz,
  varchar, uuid, varchar, varchar
) to lifemate_admin_runtime;
grant execute on function admin.update_marketing_campaign(
  uuid, uuid, varchar, varchar, varchar, varchar, uuid, timestamptz, timestamptz,
  varchar, uuid, varchar, varchar
) to lifemate_admin_runtime;
grant execute on function admin.set_marketing_campaign_status(
  uuid, uuid, varchar, varchar, uuid, varchar, varchar
) to lifemate_admin_runtime;

comment on table marketing.campaigns is
  'Canonical LifeMate marketing campaign intent/workflow. Provider publishing state, credentials and raw channel payloads do not belong here.';
comment on table marketing.campaign_events is
  'Append-only operational campaign lifecycle observations; no provider credentials or audience-level personal data.';
comment on view admin.marketing_campaigns_v1 is
  'Privacy-minimized Campaign List read model for LifeMate Command Center.';

commit;
