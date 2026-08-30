begin;

-- #617 Period Calendar trial is account/person/product scoped and server-authoritative.
create table if not exists commerce.product_trials (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references identity.accounts(id) on delete restrict,
  person_id uuid not null references core.persons(id) on delete restrict,
  product_id uuid not null references commerce.products(id) on delete restrict,
  policy_version bigint not null,
  duration_days integer not null check (duration_days between 1 and 90),
  starts_at_utc timestamptz not null,
  ends_at_utc timestamptz not null,
  created_at_utc timestamptz not null default now(),
  constraint product_trials_once_per_account_person_product unique(account_id,person_id,product_id),
  constraint product_trials_time_order check (ends_at_utc > starts_at_utc)
);

create index if not exists ix_product_trials_account_product
  on commerce.product_trials(account_id,product_id,ends_at_utc);

alter table commerce.product_trials enable row level security;
revoke all on table commerce.product_trials from public,anon,authenticated;
grant select,insert on table commerce.product_trials to lifemate_edge_runtime;

insert into commerce.catalog_policies(product_id,policy_key,value_json,value_type,status,version)
select p.id,'premium.locked_features','["circle"]'::jsonb,'json','Active',1
from commerce.products p where p.code='period-calendar'
on conflict (product_id,policy_key) do nothing;

create or replace function commerce.start_or_get_period_trial(p_app_user_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,commerce,identity,core,pg_temp
as $$
declare
  v_account uuid;
  v_person uuid;
  v_product uuid;
  v_days integer;
  v_policy_version bigint;
  v_trial commerce.product_trials%rowtype;
  v_now timestamptz := now();
begin
  v_account := identity.account_id_for_legacy_app_user(p_app_user_id);
  if v_account is null then
    return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing');
  end if;
  select l.person_id into v_person
  from core.account_person_links l
  where l.account_id=v_account and l.link_type='Self' and l.status='Active'
  order by l.created_at_utc asc limit 1;
  if v_person is null then
    return jsonb_build_object('httpStatus',409,'code','identity_person_mapping_missing');
  end if;

  select p.id into v_product from commerce.products p
  where p.code='period-calendar' and p.lifecycle_status='Published';
  if v_product is null then
    return jsonb_build_object('httpStatus',409,'code','period_product_unavailable');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account::text||':'||v_person::text||':'||v_product::text||':trial',0));

  select * into v_trial from commerce.product_trials
  where account_id=v_account and person_id=v_person and product_id=v_product;

  if not found then
    select (cp.value_json #>> '{}')::integer, cp.version
      into v_days,v_policy_version
    from commerce.catalog_policies cp
    where cp.product_id=v_product and cp.policy_key='trial.days' and cp.status='Active';
    if v_days is null or v_days not between 1 and 90 then
      return jsonb_build_object('httpStatus',409,'code','trial_policy_unavailable');
    end if;
    insert into commerce.product_trials(account_id,person_id,product_id,policy_version,duration_days,starts_at_utc,ends_at_utc)
    values(v_account,v_person,v_product,v_policy_version,v_days,v_now,v_now+make_interval(days=>v_days))
    returning * into v_trial;
  end if;

  return jsonb_build_object(
    'httpStatus',200,'code','ok','trialId',v_trial.id,
    'status',case when v_trial.ends_at_utc>v_now then 'trial_active' else 'trial_expired' end,
    'startsAtUtc',v_trial.starts_at_utc,'endsAtUtc',v_trial.ends_at_utc,
    'remainingSeconds',greatest(0,floor(extract(epoch from (v_trial.ends_at_utc-v_now)))::bigint),
    'durationDays',v_trial.duration_days,'policyVersion',v_trial.policy_version
  );
end $$;

create or replace function commerce.period_access_snapshot(p_app_user_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,commerce,identity,core,pg_temp
as $$
declare
  v_account uuid;
  v_person uuid;
  v_product uuid;
  v_trial commerce.product_trials%rowtype;
  v_paid boolean := false;
  v_locked jsonb := '[]'::jsonb;
  v_now timestamptz := now();
begin
  v_account := identity.account_id_for_legacy_app_user(p_app_user_id);
  if v_account is null then return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing'); end if;
  select l.person_id into v_person from core.account_person_links l
  where l.account_id=v_account and l.link_type='Self' and l.status='Active'
  order by l.created_at_utc asc limit 1;
  select p.id into v_product from commerce.products p where p.code='period-calendar';
  if v_person is null or v_product is null then return jsonb_build_object('httpStatus',409,'code','period_access_mapping_unavailable'); end if;

  select exists(
    select 1 from commerce.subscriptions s
    where s.owner_account_id=v_account and s.product_id=v_product
      and s.status='Active' and s.starts_at_utc<=v_now
      and (s.current_period_end_utc is null or s.current_period_end_utc>v_now)
  ) into v_paid;

  select * into v_trial from commerce.product_trials
  where account_id=v_account and person_id=v_person and product_id=v_product;

  select coalesce(cp.value_json,'[]'::jsonb) into v_locked
  from commerce.catalog_policies cp
  where cp.product_id=v_product and cp.policy_key='premium.locked_features' and cp.status='Active';

  return jsonb_build_object(
    'httpStatus',200,'code','ok','serverNowUtc',v_now,
    'state',case
      when v_paid then 'active'
      when v_trial.id is not null and v_trial.ends_at_utc>v_now then 'trial_active'
      when v_trial.id is not null then 'trial_expired'
      else 'trial_eligible'
    end,
    'hasProductAccess',v_paid or (v_trial.id is not null and v_trial.ends_at_utc>v_now),
    'paid',v_paid,
    'trial',case when v_trial.id is null then null else jsonb_build_object(
      'startsAtUtc',v_trial.starts_at_utc,'endsAtUtc',v_trial.ends_at_utc,
      'remainingSeconds',greatest(0,floor(extract(epoch from (v_trial.ends_at_utc-v_now)))::bigint)
    ) end,
    'lockedFeatures',coalesce(v_locked,'[]'::jsonb)
  );
end $$;

revoke all on function commerce.start_or_get_period_trial(uuid) from public,anon,authenticated;
revoke all on function commerce.period_access_snapshot(uuid) from public,anon,authenticated;
grant execute on function commerce.start_or_get_period_trial(uuid) to lifemate_edge_runtime;
grant execute on function commerce.period_access_snapshot(uuid) to lifemate_edge_runtime;

commit;
