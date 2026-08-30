begin;

create or replace function lifemate.women_pregnancy_transition_eligibility(
  p_app_user_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog,lifemate,commerce,identity,core,pg_temp
as $$
declare
  v_account_id uuid;
  v_person_id uuid;
  v_period_access boolean := false;
  v_cocoon_access boolean := false;
  v_women_enabled boolean := false;
begin
  v_account_id := identity.account_id_for_legacy_app_user(p_app_user_id);
  v_person_id := core.self_person_id_for_legacy_app_user(p_app_user_id);
  if v_account_id is null or v_person_id is null then
    return jsonb_build_object(
      'allowed',false,
      'reason','identity_mapping_missing'
    );
  end if;

  select exists(
    select 1
    from lifemate.women_calendar_profiles w
    where w.owner_person_id=v_person_id
      and w.enabled=true
  ) into v_women_enabled;

  select exists(
    select 1
    from commerce.subscriptions s
    join commerce.products p on p.id=s.product_id
    where s.owner_account_id=v_account_id
      and (s.beneficiary_person_id is null or s.beneficiary_person_id=v_person_id)
      and p.code='period-calendar'
      and p.status='Active'
      and s.status in ('Active','Trial')
      and coalesce(s.current_period_end_utc,'infinity'::timestamptz)>now()
  ) or exists(
    select 1
    from commerce.product_trials t
    join commerce.products p on p.id=t.product_id
    where t.account_id=v_account_id
      and t.person_id=v_person_id
      and p.code='period-calendar'
      and t.ends_at_utc>now()
  ) into v_period_access;

  select exists(
    select 1
    from commerce.subscriptions s
    join commerce.products p on p.id=s.product_id
    where s.owner_account_id=v_account_id
      and (s.beneficiary_person_id is null or s.beneficiary_person_id=v_person_id)
      and p.code='cocoonmate'
      and p.status='Active'
      and s.status in ('Active','Trial')
      and coalesce(s.current_period_end_utc,'infinity'::timestamptz)>now()
  ) into v_cocoon_access;

  if not v_women_enabled then
    return jsonb_build_object('allowed',false,'reason','women_health_not_eligible');
  end if;
  if not v_period_access then
    return jsonb_build_object('allowed',false,'reason','period_entitlement_required');
  end if;
  if not v_cocoon_access then
    return jsonb_build_object('allowed',false,'reason','cocoon_entitlement_required');
  end if;

  return jsonb_build_object(
    'allowed',true,
    'reason',null,
    'personId',v_person_id,
    'accountId',v_account_id
  );
end $$;

create or replace function lifemate.activate_women_pregnancy_mode(
  p_app_user_id uuid,
  p_idempotency_key varchar
) returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,lifemate,commerce,identity,core,pg_temp
as $$
declare
  v_eligibility jsonb;
  v_person_id uuid;
  v_account_id uuid;
  v_existing lifemate.women_health_lifecycle%rowtype;
  v_event lifemate.women_health_lifecycle_events%rowtype;
  v_now timestamptz := now();
begin
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 8 and 120 then
    return jsonb_build_object('httpStatus',400,'code','invalid_idempotency_key');
  end if;

  v_account_id := identity.account_id_for_legacy_app_user(p_app_user_id);
  v_person_id := core.self_person_id_for_legacy_app_user(p_app_user_id);
  if v_account_id is null or v_person_id is null then
    return jsonb_build_object('httpStatus',409,'code','identity_mapping_missing');
  end if;

  select * into v_event
  from lifemate.women_health_lifecycle_events
  where owner_person_id=v_person_id
    and idempotency_key=p_idempotency_key
  limit 1;
  if found then
    return jsonb_build_object(
      'httpStatus',200,
      'code','ok',
      'idempotentReplay',true,
      'state',v_event.to_state
    );
  end if;

  v_eligibility := lifemate.women_pregnancy_transition_eligibility(p_app_user_id);
  if coalesce((v_eligibility->>'allowed')::boolean,false)=false then
    return jsonb_build_object(
      'httpStatus',409,
      'code',coalesce(v_eligibility->>'reason','pregnancy_transition_unavailable')
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_person_id::text, 0));

  select * into v_existing
  from lifemate.women_health_lifecycle
  where owner_person_id=v_person_id
  for update;

  if found and v_existing.lifecycle_state='paused_for_pregnancy' then
    insert into lifemate.women_health_lifecycle_events(
      owner_person_id,from_state,to_state,reason,idempotency_key,actor_account_id
    ) values (
      v_person_id,'paused_for_pregnancy','paused_for_pregnancy','pregnancy',
      p_idempotency_key,v_account_id
    );
    return jsonb_build_object(
      'httpStatus',200,
      'code','ok',
      'idempotentReplay',false,
      'state','paused_for_pregnancy'
    );
  end if;

  if found and v_existing.lifecycle_state<>'active' then
    return jsonb_build_object(
      'httpStatus',409,
      'code','invalid_women_health_lifecycle_transition',
      'state',v_existing.lifecycle_state
    );
  end if;

  insert into lifemate.women_health_lifecycle(
    owner_person_id,lifecycle_state,pause_reason,cocoon_activation_source,
    paused_at_utc,pregnancy_mode_activated_at_utc,version,created_at_utc,updated_at_utc
  ) values (
    v_person_id,'paused_for_pregnancy','pregnancy','canonical_subscription',
    v_now,v_now,1,v_now,v_now
  )
  on conflict(owner_person_id) do update set
    lifecycle_state='paused_for_pregnancy',
    pause_reason='pregnancy',
    cocoon_activation_source='canonical_subscription',
    paused_at_utc=v_now,
    pregnancy_mode_activated_at_utc=coalesce(
      lifemate.women_health_lifecycle.pregnancy_mode_activated_at_utc,v_now
    ),
    version=lifemate.women_health_lifecycle.version+1,
    updated_at_utc=v_now;

  insert into lifemate.women_health_lifecycle_events(
    owner_person_id,from_state,to_state,reason,idempotency_key,actor_account_id
  ) values (
    v_person_id,'active','paused_for_pregnancy','pregnancy',
    p_idempotency_key,v_account_id
  );

  update lifemate.women_calendar_profiles
  set reminders_enabled=false,
      version=version+1,
      updated_at_utc=v_now
  where owner_person_id=v_person_id;

  return jsonb_build_object(
    'httpStatus',200,
    'code','ok',
    'idempotentReplay',false,
    'state','paused_for_pregnancy'
  );
end $$;

revoke all on function lifemate.women_pregnancy_transition_eligibility(uuid) from public;
revoke all on function lifemate.activate_women_pregnancy_mode(uuid,varchar) from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format(
        'revoke all on function lifemate.women_pregnancy_transition_eligibility(uuid) from %I',
        v_role
      );
      execute format(
        'revoke all on function lifemate.activate_women_pregnancy_mode(uuid,varchar) from %I',
        v_role
      );
    end if;
  end loop;
  if exists(select 1 from pg_roles where rolname='lifemate_api_runtime') then
    grant execute on function lifemate.women_pregnancy_transition_eligibility(uuid)
      to lifemate_api_runtime;
    grant execute on function lifemate.activate_women_pregnancy_mode(uuid,varchar)
      to lifemate_api_runtime;
  end if;
end $$;

comment on function lifemate.activate_women_pregnancy_mode(uuid,varchar) is
  'Idempotent self-person pregnancy transition. Requires canonical Period + Cocoon commercial access and never grants entitlement or expands sharing.';

commit;