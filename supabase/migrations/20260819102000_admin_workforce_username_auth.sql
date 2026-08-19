-- Username/password workforce authentication support for LifeMate Command Center.
--
-- Passwords remain exclusively in Supabase Auth. This migration only provides a
-- privacy-minimized username -> Supabase Auth subject resolver and a controlled
-- pending-staff registration transaction. Self-registration NEVER grants a role.

create table if not exists admin.workforce_auth_limits (
    key_hash character varying(128) primary key,
    window_started_at_utc timestamp with time zone not null default now(),
    attempt_count integer not null default 0 check (attempt_count >= 0),
    updated_at_utc timestamp with time zone not null default now()
);

alter table admin.workforce_auth_limits enable row level security;
alter table admin.workforce_auth_limits force row level security;

revoke all on admin.workforce_auth_limits from public;
do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on admin.workforce_auth_limits from %I', v_role);
    end if;
  end loop;
end
$$;

-- The Edge auth boundary calls this through the existing restricted Admin runtime
-- connection. Returning only an opaque Auth user UUID keeps email out of browser UX.
create or replace function admin.resolve_workforce_auth_subject(
    p_username text
) returns uuid
language sql
stable
security definer
set search_path = admin, identity, pg_temp
as $$
    select ei.provider_subject::uuid
    from admin.staff_profiles sp
    join admin.members m on m.account_id=sp.account_id
    join identity.external_identities ei on ei.account_id=sp.account_id
    where lower(sp.username)=lower(trim(p_username))
      and m.status in ('Active','Disabled')
      and ei.provider='supabase_auth'
      and ei.issuer='supabase'
      and ei.status='Active'
      and ei.provider_subject ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    order by ei.created_at_utc desc
    limit 1
$$;

-- Rate limiting is intentionally database-backed so multiple Edge workers share the
-- same throttle state. The caller passes only a SHA-256 fingerprint, never raw IP.
create or replace function admin.consume_workforce_auth_attempt(
    p_key_hash text,
    p_limit integer default 8,
    p_window_seconds integer default 600
) returns boolean
language plpgsql
security definer
set search_path = admin, pg_temp
as $$
declare
  v_row admin.workforce_auth_limits%rowtype;
begin
  if p_key_hash !~ '^[0-9a-f]{64}$' or p_limit < 1 or p_limit > 100
     or p_window_seconds < 60 or p_window_seconds > 86400 then
    return false;
  end if;

  insert into admin.workforce_auth_limits(key_hash, window_started_at_utc, attempt_count, updated_at_utc)
  values (p_key_hash, now(), 1, now())
  on conflict (key_hash) do update set
    window_started_at_utc = case
      when admin.workforce_auth_limits.window_started_at_utc <= now() - make_interval(secs => p_window_seconds)
        then now()
      else admin.workforce_auth_limits.window_started_at_utc
    end,
    attempt_count = case
      when admin.workforce_auth_limits.window_started_at_utc <= now() - make_interval(secs => p_window_seconds)
        then 1
      else admin.workforce_auth_limits.attempt_count + 1
    end,
    updated_at_utc = now()
  returning * into v_row;

  return v_row.attempt_count <= p_limit;
end
$$;

-- Called only after Supabase Auth Admin successfully created the workforce auth user.
-- The new account is Disabled in the Admin control plane until Founder assigns a role.
create or replace function admin.register_pending_workforce_account(
    p_auth_user_id uuid,
    p_username text,
    p_display_name text,
    p_correlation_id uuid
) returns uuid
language plpgsql
security definer
set search_path = admin, identity, pg_temp
as $$
declare
  v_username text := lower(trim(p_username));
  v_display_name text := trim(coalesce(nullif(p_display_name,''), p_username));
  v_account_id uuid := gen_random_uuid();
begin
  if v_username !~ '^[a-z0-9][a-z0-9._-]{2,31}$' then
    raise exception 'invalid_workforce_username' using errcode='22023';
  end if;
  if length(v_display_name) < 2 or length(v_display_name) > 120 then
    raise exception 'invalid_workforce_display_name' using errcode='22023';
  end if;
  if exists (select 1 from admin.staff_profiles where lower(username)=v_username) then
    raise exception 'workforce_username_unavailable' using errcode='23505';
  end if;
  if exists (
    select 1 from identity.external_identities
    where provider='supabase_auth' and issuer='supabase' and provider_subject=p_auth_user_id::text
  ) then
    raise exception 'workforce_auth_identity_exists' using errcode='23505';
  end if;

  insert into identity.accounts(id,status)
  values (v_account_id,'Active');

  insert into identity.external_identities(
    account_id,provider,issuer,provider_subject,status,last_authenticated_at_utc
  ) values (
    v_account_id,'supabase_auth','supabase',p_auth_user_id::text,'Active',null
  );

  insert into admin.members(account_id,status,created_by_account_id)
  values (v_account_id,'Disabled',null);

  insert into admin.staff_profiles(account_id,username,display_name)
  values (v_account_id,v_username,v_display_name);

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,request_id,elevated_access,metadata_json
  ) values (
    null,'security.staff.self_register','admin_member',v_account_id::text,
    'Succeeded','Pending Founder role assignment',p_correlation_id,
    null,false,jsonb_build_object('registration_state','pending_role')
  );

  return v_account_id;
end
$$;

revoke all on function admin.resolve_workforce_auth_subject(text) from public;
revoke all on function admin.consume_workforce_auth_attempt(text,integer,integer) from public;
revoke all on function admin.register_pending_workforce_account(uuid,text,text,uuid) from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on function admin.resolve_workforce_auth_subject(text) from %I', v_role);
      execute format('revoke all on function admin.consume_workforce_auth_attempt(text,integer,integer) from %I', v_role);
      execute format('revoke all on function admin.register_pending_workforce_account(uuid,text,text,uuid) from %I', v_role);
    end if;
  end loop;
end
$$;

grant execute on function admin.resolve_workforce_auth_subject(text) to lifemate_admin_runtime;
grant execute on function admin.consume_workforce_auth_attempt(text,integer,integer) to lifemate_admin_runtime;
grant execute on function admin.register_pending_workforce_account(uuid,text,text,uuid) to lifemate_admin_runtime;

comment on function admin.register_pending_workforce_account(uuid,text,text,uuid) is
  'Creates a Disabled Command Center member/profile for a Supabase Auth workforce identity. Does not grant any role or permission.';
