begin;

create table if not exists admin.command_center_preferences (
  scope character varying(64) primary key,
  locale character varying(16) not null,
  time_zone character varying(64) not null,
  display_name character varying(120) not null,
  version integer not null default 1 check (version > 0),
  updated_by_account_id uuid references identity.accounts(id) on delete set null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (scope = 'command_center'),
  check (locale in ('fa-IR','en-US')),
  check (length(trim(display_name)) between 1 and 120)
);

alter table admin.command_center_preferences enable row level security;
alter table admin.command_center_preferences force row level security;
drop policy if exists command_center_preferences_no_direct_access on admin.command_center_preferences;
create policy command_center_preferences_no_direct_access
  on admin.command_center_preferences for all using (false) with check (false);

insert into admin.command_center_preferences(scope, locale, time_zone, display_name)
values ('command_center','fa-IR','Asia/Tehran','LifeMate Command Center')
on conflict (scope) do nothing;

create or replace function admin.get_command_center_preferences()
returns table(
  locale character varying,
  time_zone character varying,
  display_name character varying,
  version integer,
  updated_at_utc timestamptz
)
language sql
security definer
set search_path = admin, pg_temp
as $$
  select p.locale, p.time_zone, p.display_name, p.version, p.updated_at_utc
  from admin.command_center_preferences p
  where p.scope = 'command_center';
$$;

revoke all on function admin.get_command_center_preferences() from public;
grant execute on function admin.get_command_center_preferences() to lifemate_admin_runtime;

create or replace function admin.configure_command_center_preferences(
  p_actor_account_id uuid,
  p_locale character varying,
  p_time_zone character varying,
  p_display_name character varying,
  p_expected_version integer,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, pg_catalog, pg_temp
as $$
declare
  v_operation constant character varying := 'settings.preferences.configure';
  v_existing admin.idempotency_keys%rowtype;
  v_preferences admin.command_center_preferences%rowtype;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'settings.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;

  if p_locale not in ('fa-IR','en-US')
     or p_time_zone is null or length(trim(p_time_zone)) not between 1 and 64
     or not exists (select 1 from pg_timezone_names where name = trim(p_time_zone))
     or p_display_name is null or length(trim(p_display_name)) not between 1 and 120
     or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object('httpStatus',400,'code','settings_invalid','message','One or more settings values are invalid.','replayed',false);
  end if;

  if p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','settings_request_invalid','message','Settings request metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id = p_actor_account_id and operation = v_operation and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status = 'Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values (p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  perform pg_advisory_xact_lock(hashtextextended('admin.command_center_preferences',0));
  select * into v_preferences
  from admin.command_center_preferences
  where scope = 'command_center'
  for update;

  if not found then
    v_response := jsonb_build_object('httpStatus',503,'code','settings_unavailable','message','Command Center preferences are unavailable.','replayed',false);
  elsif v_preferences.version <> p_expected_version then
    v_response := jsonb_build_object('httpStatus',409,'code','settings_version_conflict','message','Settings version does not match.','replayed',false);
  else
    update admin.command_center_preferences
    set locale = p_locale,
        time_zone = trim(p_time_zone),
        display_name = trim(p_display_name),
        version = version + 1,
        updated_by_account_id = p_actor_account_id,
        updated_at_utc = now()
    where scope = 'command_center'
    returning * into v_preferences;

    v_response := jsonb_build_object(
      'httpStatus',200,
      'code','ok',
      'locale',v_preferences.locale,
      'timeZone',v_preferences.time_zone,
      'displayName',v_preferences.display_name,
      'version',v_preferences.version,
      'updatedAtUtc',v_preferences.updated_at_utc,
      'replayed',false
    );
  end if;

  insert into admin.audit_events(
    actor_account_id, action, resource_type, resource_id, result, reason,
    correlation_id, request_id, elevated_access, metadata_json
  ) values (
    p_actor_account_id, v_operation, 'command_center_preferences', 'command_center',
    case when (v_response->>'httpStatus')::integer < 400 then 'Succeeded' else 'Denied' end,
    trim(p_reason), p_correlation_id, p_idempotency_key, false,
    jsonb_build_object(
      'code',v_response->>'code',
      'locale',p_locale,
      'timeZone',trim(p_time_zone),
      'expectedVersion',p_expected_version,
      'displayNameChanged',true
    )
  );

  update admin.idempotency_keys
  set status='Completed', response_status=(v_response->>'httpStatus')::integer,
      response_json=v_response, updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;

  return v_response;
end $$;

revoke all on function admin.configure_command_center_preferences(
  uuid,character varying,character varying,character varying,integer,character varying,uuid,character varying,character varying
) from public;
grant execute on function admin.configure_command_center_preferences(
  uuid,character varying,character varying,character varying,integer,character varying,uuid,character varying,character varying
) to lifemate_admin_runtime;

commit;
