begin;

create schema if not exists marketing;

create table if not exists marketing.channel_connections (
  provider_code varchar(64) primary key
    check (provider_code ~ '^[a-z0-9][a-z0-9_.:-]{0,63}$'),
  display_name varchar(120) not null check (length(trim(display_name)) between 2 and 120),
  operator_status varchar(24) not null default 'Enabled'
    check (operator_status in ('Enabled','Disabled')),
  credential_secret_name varchar(180) not null unique
    check (credential_secret_name ~ '^lifemate_marketing_[a-z0-9_:-]+_token$'),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  updated_by_admin_account_id uuid references admin.members(account_id) on delete set null
);

insert into marketing.channel_connections(
  provider_code, display_name, operator_status, credential_secret_name
) values
  ('instagram','Instagram','Enabled','lifemate_marketing_instagram_token'),
  ('facebook','Facebook','Enabled','lifemate_marketing_facebook_token'),
  ('linkedin','LinkedIn','Enabled','lifemate_marketing_linkedin_token'),
  ('telegram','Telegram','Enabled','lifemate_marketing_telegram_token')
on conflict (provider_code) do update set
  display_name = excluded.display_name,
  credential_secret_name = excluded.credential_secret_name,
  updated_at_utc = now();

create or replace function admin.marketing_channel_credential_available(
  p_provider_code varchar
) returns boolean
language plpgsql
security definer
set search_path = admin, marketing, pg_temp
as $$
declare
  v_secret_name varchar;
  v_available boolean := false;
begin
  select credential_secret_name
    into v_secret_name
  from marketing.channel_connections
  where provider_code = p_provider_code;

  if v_secret_name is null or to_regnamespace('vault') is null then
    return false;
  end if;

  begin
    execute $sql$
      select exists(
        select 1
        from vault.decrypted_secrets
        where name = $1
          and decrypted_secret is not null
          and length(decrypted_secret) > 0
      )
    $sql$ into v_available using v_secret_name;
  exception when others then
    return false;
  end;

  return coalesce(v_available, false);
end
$$;

create or replace view admin.marketing_channel_connections_v1
with (security_invoker = true)
as
select
  c.provider_code,
  c.display_name,
  c.operator_status,
  case
    when c.operator_status = 'Disabled' then 'Disabled'
    when admin.marketing_channel_credential_available(c.provider_code) then 'CredentialAvailable'
    else 'SetupRequired'
  end as setup_status,
  admin.marketing_channel_credential_available(c.provider_code) as credential_available,
  c.updated_at_utc
from marketing.channel_connections c;

revoke all on schema marketing from public;
revoke all on marketing.channel_connections from public;
revoke all on admin.marketing_channel_connections_v1 from public;
revoke all on function admin.marketing_channel_credential_available(varchar) from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if to_regrole(v_role) is not null then
      execute format('revoke all on schema marketing from %I', v_role);
      execute format('revoke all on marketing.channel_connections from %I', v_role);
      execute format('revoke all on admin.marketing_channel_connections_v1 from %I', v_role);
      execute format('revoke all on function admin.marketing_channel_credential_available(varchar) from %I', v_role);
    end if;
  end loop;
end
$$;

grant usage on schema marketing to lifemate_admin_runtime;
grant select on marketing.channel_connections to lifemate_admin_runtime;
grant select on admin.marketing_channel_connections_v1 to lifemate_admin_runtime;
grant execute on function admin.marketing_channel_credential_available(varchar) to lifemate_admin_runtime;

create or replace function admin.set_marketing_channel_operator_status(
  p_actor_account_id uuid,
  p_provider_code varchar,
  p_enabled boolean,
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
  v_operation varchar := 'marketing.channel.status:' || p_provider_code;
  v_existing admin.idempotency_keys%rowtype;
  v_current marketing.channel_connections%rowtype;
  v_target varchar := case when p_enabled then 'Enabled' else 'Disabled' end;
  v_setup_status varchar;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'marketing.social.publish') then
    return jsonb_build_object(
      'httpStatus', 403,
      'code', 'permission_denied',
      'message', 'The required high-risk marketing permission is not granted.',
      'replayed', false
    );
  end if;

  if p_provider_code is null or p_provider_code !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$' then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_channel_invalid', 'message', 'Channel provider is invalid.', 'replayed', false);
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object('httpStatus', 400, 'code', 'marketing_channel_reason_invalid', 'message', 'A reason between 10 and 1000 characters is required.', 'replayed', false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus', 400, 'code', 'idempotency_invalid', 'message', 'Idempotency metadata is invalid.', 'replayed', false);
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key, 0)
  );

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
  from marketing.channel_connections
  where provider_code = p_provider_code
  for update;

  if not found then
    v_response := jsonb_build_object('httpStatus', 404, 'code', 'marketing_channel_not_found', 'message', 'Channel provider was not found.', 'replayed', false);
  else
    update marketing.channel_connections
    set operator_status = v_target,
        updated_at_utc = now(),
        updated_by_admin_account_id = p_actor_account_id
    where provider_code = p_provider_code;

    v_setup_status := case
      when v_target = 'Disabled' then 'Disabled'
      when admin.marketing_channel_credential_available(p_provider_code) then 'CredentialAvailable'
      else 'SetupRequired'
    end;

    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id,
      'marketing.channel.status',
      'marketing_channel',
      p_provider_code,
      'Succeeded',
      trim(p_reason),
      p_correlation_id,
      p_idempotency_key,
      false,
      jsonb_build_object(
        'fromStatus', v_current.operator_status,
        'toStatus', v_target,
        'setupStatus', v_setup_status
      )
    );

    v_response := jsonb_build_object(
      'httpStatus', 200,
      'code', 'ok',
      'providerCode', p_provider_code,
      'operatorStatus', v_target,
      'setupStatus', v_setup_status,
      'replayed', false
    );
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id,
      'marketing.channel.status',
      'marketing_channel',
      p_provider_code,
      'Denied',
      coalesce(v_response->>'message', 'Channel status update denied'),
      p_correlation_id,
      p_idempotency_key,
      false,
      jsonb_build_object('code', v_response->>'code')
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

revoke all on function admin.set_marketing_channel_operator_status(
  uuid, varchar, boolean, varchar, uuid, varchar, varchar
) from public;
grant execute on function admin.set_marketing_channel_operator_status(
  uuid, varchar, boolean, varchar, uuid, varchar, varchar
) to lifemate_admin_runtime;

comment on table marketing.channel_connections is
  'Server-side social channel registry. Credential secret names are server-only metadata; token values remain in Vault and are never exposed by Admin read models.';
comment on view admin.marketing_channel_connections_v1 is
  'Privacy-minimized channel setup/status read model. Credential values are never projected.';

commit;
