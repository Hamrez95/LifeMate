begin;

create or replace function admin.read_growth_active_user_metrics_v1(
  p_date date,
  p_product varchar default null
) returns table(
  definition_version smallint,
  first_event_at_utc timestamptz,
  latest_event_at_utc timestamptz,
  day_started boolean,
  instrumented_by_day_end boolean,
  dau_coverage_complete boolean,
  wau_coverage_complete boolean,
  mau_coverage_complete boolean,
  dau integer,
  wau integer,
  mau integer,
  new_dau integer,
  returning_dau integer
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with bounds as (
    select
      (p_date::timestamp at time zone 'Asia/Tehran') as day_start,
      ((p_date + 1)::timestamp at time zone 'Asia/Tehran') as day_end,
      ((p_date - 6)::timestamp at time zone 'Asia/Tehran') as wau_start,
      ((p_date - 29)::timestamp at time zone 'Asia/Tehran') as mau_start
  ),
  scoped as (
    select
      e.account_id,
      e.received_at_utc,
      a.created_at_utc
    from analytics.product_activity_events e
    join identity.accounts a on a.id = e.account_id
    where e.event_name = 'app_opened'
      and e.outcome = 'success'
      and (p_product is null or e.product = lower(p_product))
  ),
  coverage as (
    select
      min(received_at_utc) as first_event_at_utc,
      max(received_at_utc) as latest_event_at_utc
    from scoped
  )
  select
    1::smallint as definition_version,
    c.first_event_at_utc,
    c.latest_event_at_utc,
    now() >= b.day_start as day_started,
    c.first_event_at_utc is not null and c.first_event_at_utc < b.day_end as instrumented_by_day_end,
    c.first_event_at_utc is not null and c.first_event_at_utc <= b.day_start as dau_coverage_complete,
    c.first_event_at_utc is not null and c.first_event_at_utc <= b.wau_start as wau_coverage_complete,
    c.first_event_at_utc is not null and c.first_event_at_utc <= b.mau_start as mau_coverage_complete,
    count(distinct s.account_id) filter (
      where s.received_at_utc >= b.day_start and s.received_at_utc < b.day_end
    )::integer as dau,
    count(distinct s.account_id) filter (
      where s.received_at_utc >= b.wau_start and s.received_at_utc < b.day_end
    )::integer as wau,
    count(distinct s.account_id) filter (
      where s.received_at_utc >= b.mau_start and s.received_at_utc < b.day_end
    )::integer as mau,
    count(distinct s.account_id) filter (
      where s.received_at_utc >= b.day_start
        and s.received_at_utc < b.day_end
        and s.created_at_utc >= b.day_start
        and s.created_at_utc < b.day_end
    )::integer as new_dau,
    count(distinct s.account_id) filter (
      where s.received_at_utc >= b.day_start
        and s.received_at_utc < b.day_end
        and s.created_at_utc < b.day_start
    )::integer as returning_dau
  from bounds b
  cross join coverage c
  left join scoped s on true
  group by
    b.day_start,
    b.day_end,
    b.wau_start,
    b.mau_start,
    c.first_event_at_utc,
    c.latest_event_at_utc;
$$;

comment on function admin.read_growth_active_user_metrics_v1(date,varchar) is
  'Aggregate-only active-user read model from successful canonical app_opened facts. Distinct account semantics; company scope deduplicates accounts across products. Returns no account identifiers or raw events.';

revoke all on function admin.read_growth_active_user_metrics_v1(date,varchar) from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated','lifemate_edge_runtime','lifemate_worker_runtime'] loop
    if exists (select 1 from pg_roles where rolname = v_role) then
      execute format('revoke all on function admin.read_growth_active_user_metrics_v1(date,varchar) from %I', v_role);
    end if;
  end loop;

  if exists (select 1 from pg_roles where rolname = 'lifemate_admin_runtime') then
    grant execute on function admin.read_growth_active_user_metrics_v1(date,varchar) to lifemate_admin_runtime;
  end if;
end $$;

commit;
