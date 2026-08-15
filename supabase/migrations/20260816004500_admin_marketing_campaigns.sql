begin;

create schema if not exists marketing;

create table if not exists marketing.campaigns (
  id uuid primary key default gen_random_uuid(),
  name varchar(160) not null,
  objective varchar(500),
  product_code varchar(64),
  status varchar(24) not null default 'Draft'
    check (status in ('Draft','Ready','Active','Paused','Completed','Cancelled')),
  starts_at_utc timestamptz,
  ends_at_utc timestamptz,
  owner_admin_account_id uuid references admin.members(account_id) on delete set null,
  created_by_admin_account_id uuid not null references admin.members(account_id) on delete restrict,
  updated_by_admin_account_id uuid not null references admin.members(account_id) on delete restrict,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (product_code is null or product_code ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  check (ends_at_utc is null or starts_at_utc is null or ends_at_utc >= starts_at_utc)
);

create index if not exists ix_marketing_campaigns_status_updated
  on marketing.campaigns(status, updated_at_utc desc, id desc);
create index if not exists ix_marketing_campaigns_product_status_updated
  on marketing.campaigns(product_code, status, updated_at_utc desc, id desc)
  where product_code is not null;
create index if not exists ix_marketing_campaigns_owner_status_updated
  on marketing.campaigns(owner_admin_account_id, status, updated_at_utc desc, id desc)
  where owner_admin_account_id is not null;

create table if not exists marketing.campaign_events (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references marketing.campaigns(id) on delete cascade,
  event_type varchar(40) not null
    check (event_type in ('Created','StatusChanged')),
  from_status varchar(24),
  to_status varchar(24) not null
    check (to_status in ('Draft','Ready','Active','Paused','Completed','Cancelled')),
  reason varchar(500),
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

comment on table marketing.campaigns is
  'Canonical LifeMate marketing campaign intent/workflow. Provider publishing state, credentials and raw channel payloads do not belong here.';
comment on table marketing.campaign_events is
  'Append-only operational campaign lifecycle observations; no provider credentials or audience-level personal data.';
comment on view admin.marketing_campaigns_v1 is
  'Privacy-minimized Campaign List read model for LifeMate Command Center.';

commit;
