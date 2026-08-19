-- One-time Founder password activation for Command Center bootstrap.
--
-- The raw activation code is never stored. Only a SHA-256 token hash is persisted,
-- and the flow is restricted to an active Founder account. Password material remains
-- exclusively in Supabase Auth and is never written to these tables.

create table if not exists admin.workforce_founder_activations (
    account_id uuid primary key references admin.members(account_id) on delete cascade,
    token_hash character varying(64) not null unique,
    expires_at_utc timestamp with time zone not null,
    consumed_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    check (token_hash ~ '^[0-9a-f]{64}$')
);

alter table admin.workforce_founder_activations enable row level security;
alter table admin.workforce_founder_activations force row level security;
revoke all on admin.workforce_founder_activations from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on admin.workforce_founder_activations from %I', v_role);
    end if;
  end loop;
end
$$;

create or replace function admin.resolve_founder_password_activation(
    p_username text,
    p_token_hash text
) returns uuid
language sql
stable
security definer
set search_path = admin, identity, pg_temp
as $$
    select ei.provider_subject::uuid
    from admin.workforce_founder_activations a
    join admin.members m on m.account_id=a.account_id
    join admin.staff_profiles sp on sp.account_id=m.account_id
    join admin.member_roles mr on mr.account_id=m.account_id
    join admin.roles r on r.id=mr.role_id
    join identity.external_identities ei on ei.account_id=m.account_id
    where lower(sp.username)=lower(trim(p_username))
      and a.token_hash=p_token_hash
      and a.consumed_at_utc is null
      and a.expires_at_utc > now()
      and m.status='Active'
      and r.code='founder'
      and r.status='Active'
      and mr.revoked_at_utc is null
      and mr.starts_at_utc <= now()
      and (mr.expires_at_utc is null or mr.expires_at_utc > now())
      and ei.provider='supabase_auth'
      and ei.issuer='supabase'
      and ei.status='Active'
      and ei.provider_subject ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    limit 1
$$;

create or replace function admin.consume_founder_password_activation(
    p_username text,
    p_token_hash text
) returns boolean
language plpgsql
security definer
set search_path = admin, pg_temp
as $$
declare
  v_count integer;
begin
  update admin.workforce_founder_activations a
  set consumed_at_utc=now(), updated_at_utc=now()
  from admin.staff_profiles sp, admin.members m
  where sp.account_id=a.account_id
    and m.account_id=a.account_id
    and lower(sp.username)=lower(trim(p_username))
    and a.token_hash=p_token_hash
    and a.consumed_at_utc is null
    and a.expires_at_utc > now()
    and m.status='Active'
    and exists (
      select 1
      from admin.member_roles mr
      join admin.roles r on r.id=mr.role_id
      where mr.account_id=a.account_id
        and r.code='founder'
        and r.status='Active'
        and mr.revoked_at_utc is null
        and mr.starts_at_utc <= now()
        and (mr.expires_at_utc is null or mr.expires_at_utc > now())
    );
  get diagnostics v_count = row_count;
  return v_count = 1;
end
$$;

revoke all on function admin.resolve_founder_password_activation(text,text) from public;
revoke all on function admin.consume_founder_password_activation(text,text) from public;
grant execute on function admin.resolve_founder_password_activation(text,text) to lifemate_admin_runtime;
grant execute on function admin.consume_founder_password_activation(text,text) to lifemate_admin_runtime;

comment on table admin.workforce_founder_activations is
  'One-time SHA-256 activation token hashes for Founder password bootstrap. Never stores passwords or raw activation codes.';
