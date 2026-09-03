begin;

create schema if not exists analytics;

create table if not exists analytics.product_activity_events (
  event_id uuid primary key,
  account_id uuid not null references identity.accounts(id) on delete cascade,
  product varchar(16) not null check (product in ('wellmate','caremate')),
  event_name varchar(64) not null check (
    event_name in (
      'app_opened',
      'auth_login_succeeded',
      'auth_session_restored',
      'onboarding_started',
      'onboarding_completed',
      'care_pairing_started',
      'care_pairing_completed',
      'care_access_revoked',
      'offline_queue_enqueued',
      'offline_queue_recovered'
    )
  ),
  definition_version smallint not null default 1 check (definition_version between 1 and 32767),
  release_version varchar(80) not null check (release_version ~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$'),
  platform varchar(16) not null check (platform in ('android','ios','web','windows','macos','linux','unknown')),
  locale_family varchar(8) not null check (locale_family in ('fa','en','other')),
  connectivity varchar(16) not null check (connectivity in ('online','offline','recovering','unknown')),
  outcome varchar(20) not null check (outcome in ('success','failure','cancelled','queued','replayed','not_applicable')),
  received_at_utc timestamptz not null default now()
);

comment on table analytics.product_activity_events is
  'Privacy-safe append-only product activity facts. Never store PHI, free text, contact values, provider secrets or arbitrary client metadata.';
comment on column analytics.product_activity_events.account_id is
  'Canonical LifeMate account resolved server-side from the authenticated JWT subject; never accepted from the client payload.';
comment on column analytics.product_activity_events.received_at_utc is
  'Server receive time and the canonical v1 activity clock. Client clock is intentionally not trusted in v1.';

create index if not exists ix_product_activity_event_time
  on analytics.product_activity_events(event_name, received_at_utc desc);
create index if not exists ix_product_activity_product_event_time
  on analytics.product_activity_events(product, event_name, received_at_utc desc);
create index if not exists ix_product_activity_account_event_time
  on analytics.product_activity_events(account_id, event_name, received_at_utc desc);

alter table analytics.product_activity_events enable row level security;
revoke all on table analytics.product_activity_events from public, anon, authenticated;

create or replace function public.record_product_activity_event(
  p_event_id uuid,
  p_product varchar,
  p_event_name varchar,
  p_definition_version smallint,
  p_release_version varchar,
  p_platform varchar,
  p_locale_family varchar,
  p_connectivity varchar,
  p_outcome varchar
) returns varchar
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_account_id uuid;
  v_auth_subject text;
  v_rows integer;
begin
  v_auth_subject := coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  );

  if v_auth_subject is null
     or v_auth_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception using errcode = '42501', message = 'analytics_auth_required';
  end if;

  select a.id
    into v_account_id
    from lifemate.app_users u
    join identity.accounts a on a.legacy_app_user_id = u.id
   where u.auth_subject = lower(v_auth_subject)
     and u.status = 'Active'
   limit 1;

  if v_account_id is null then
    raise exception using errcode = '42501', message = 'analytics_account_unmapped';
  end if;

  if p_product not in ('wellmate','caremate') then
    raise exception using errcode = '22023', message = 'analytics_product_invalid';
  end if;
  if p_event_name not in (
    'app_opened',
    'auth_login_succeeded',
    'auth_session_restored',
    'onboarding_started',
    'onboarding_completed',
    'care_pairing_started',
    'care_pairing_completed',
    'care_access_revoked',
    'offline_queue_enqueued',
    'offline_queue_recovered'
  ) then
    raise exception using errcode = '22023', message = 'analytics_event_invalid';
  end if;
  if p_definition_version is null or p_definition_version < 1 then
    raise exception using errcode = '22023', message = 'analytics_definition_version_invalid';
  end if;

  insert into analytics.product_activity_events(
    event_id,
    account_id,
    product,
    event_name,
    definition_version,
    release_version,
    platform,
    locale_family,
    connectivity,
    outcome
  ) values (
    p_event_id,
    v_account_id,
    p_product,
    p_event_name,
    p_definition_version,
    p_release_version,
    p_platform,
    p_locale_family,
    p_connectivity,
    p_outcome
  )
  on conflict (event_id) do nothing;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return 'duplicate';
  end if;
  return 'inserted';
end;
$$;

revoke all on function public.record_product_activity_event(uuid,varchar,varchar,smallint,varchar,varchar,varchar,varchar,varchar) from public, anon;
grant execute on function public.record_product_activity_event(uuid,varchar,varchar,smallint,varchar,varchar,varchar,varchar,varchar) to authenticated;

comment on function public.record_product_activity_event(uuid,varchar,varchar,smallint,varchar,varchar,varchar,varchar,varchar) is
  'Narrow authenticated ingestion contract for privacy-safe product activity. Resolves canonical account from the verified JWT subject, deduplicates by event_id and accepts no arbitrary metadata.';

commit;
