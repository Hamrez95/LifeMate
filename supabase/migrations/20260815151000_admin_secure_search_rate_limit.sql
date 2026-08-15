begin;

-- ADM-PLAT-002: database-backed per-admin search throttling. The Admin API
-- calls the SECURITY DEFINER function; lifemate_admin_runtime never receives
-- direct table access. Search query text is deliberately not persisted.
create table if not exists admin.search_rate_limits (
  account_id uuid primary key references admin.members(account_id) on delete cascade,
  window_started_at_utc timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0),
  updated_at_utc timestamptz not null default now()
);

revoke all on admin.search_rate_limits from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on admin.search_rate_limits from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on admin.search_rate_limits from authenticated';
  end if;
  if to_regrole('lifemate_admin_runtime') is not null then
    execute 'revoke all on admin.search_rate_limits from lifemate_admin_runtime';
  end if;
end
$$;

create or replace function admin.consume_search_rate_limit(
  p_account_id uuid,
  p_limit integer default 60,
  p_window_seconds integer default 60
) returns table(allowed boolean, remaining integer, retry_after_seconds integer)
language plpgsql
security definer
set search_path = admin, pg_temp
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_started timestamptz;
  v_count integer;
  v_elapsed numeric;
begin
  if p_limit < 1 or p_limit > 600 or p_window_seconds < 10 or p_window_seconds > 3600 then
    raise exception 'search rate limit configuration is outside allowed bounds';
  end if;

  if not exists (
    select 1 from admin.members m where m.account_id = p_account_id and m.status = 'Active'
  ) then
    return query select false, 0, p_window_seconds;
    return;
  end if;

  insert into admin.search_rate_limits(account_id, window_started_at_utc, request_count, updated_at_utc)
  values (p_account_id, v_now, 0, v_now)
  on conflict (account_id) do nothing;

  select window_started_at_utc, request_count
    into v_started, v_count
  from admin.search_rate_limits
  where account_id = p_account_id
  for update;

  v_elapsed := extract(epoch from (v_now - v_started));

  if v_elapsed >= p_window_seconds then
    update admin.search_rate_limits
      set window_started_at_utc = v_now,
          request_count = 1,
          updated_at_utc = v_now
    where account_id = p_account_id;
    return query select true, greatest(p_limit - 1, 0), 0;
    return;
  end if;

  if v_count >= p_limit then
    return query
      select false,
             0,
             greatest(1, ceil(p_window_seconds - v_elapsed)::integer);
    return;
  end if;

  update admin.search_rate_limits
    set request_count = request_count + 1,
        updated_at_utc = v_now
  where account_id = p_account_id;

  return query select true, greatest(p_limit - (v_count + 1), 0), 0;
end
$$;

revoke all on function admin.consume_search_rate_limit(uuid, integer, integer) from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on function admin.consume_search_rate_limit(uuid, integer, integer) from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on function admin.consume_search_rate_limit(uuid, integer, integer) from authenticated';
  end if;
end
$$;

grant execute on function admin.consume_search_rate_limit(uuid, integer, integer)
  to lifemate_admin_runtime;

comment on table admin.search_rate_limits is
  'Per-admin Command Center search throttle state. Raw search query text is never stored.';
comment on function admin.consume_search_rate_limit(uuid, integer, integer) is
  'Atomically consumes one Command Center global-search request for an active admin member.';

commit;
