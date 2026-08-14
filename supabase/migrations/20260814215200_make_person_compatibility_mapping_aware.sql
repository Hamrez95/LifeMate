-- Provider-agnostic compatibility helpers.
--
-- Legacy API tables still carry app-user UUIDs while the ecosystem authority is
-- Account -> Self Person. These helpers are deliberately narrow SECURITY DEFINER
-- lookups so trigger code can resolve the bridge without granting broad identity
-- table reads to every runtime role.
create or replace function identity.account_id_for_legacy_app_user(p_app_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, identity, pg_temp
as $$
  select a.id
  from identity.accounts a
  where a.legacy_app_user_id = p_app_user_id
    and a.status <> 'Deleted'
  order by a.created_at_utc,a.id
  limit 1
$$;

create or replace function core.self_person_id_for_legacy_app_user(p_app_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, identity, core, pg_temp
as $$
  select l.person_id
  from identity.accounts a
  join core.account_person_links l
    on l.account_id=a.id
   and l.link_type='Self'
   and l.status='Active'
  where a.legacy_app_user_id=p_app_user_id
    and a.status <> 'Deleted'
  order by l.created_at_utc,l.person_id
  limit 1
$$;

revoke all on function identity.account_id_for_legacy_app_user(uuid) from public;
revoke all on function core.self_person_id_for_legacy_app_user(uuid) from public;
grant execute on function identity.account_id_for_legacy_app_user(uuid)
  to lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function core.self_person_id_for_legacy_app_user(uuid)
  to lifemate_edge_runtime,lifemate_worker_runtime;

-- User-profile compatibility projection must follow the mapped Self Person; a
-- provider-agnostic Account UUID is not required to equal either AppUser or Person.
create or replace function core.sync_legacy_user_profile()
returns trigger
language plpgsql
set search_path = pg_catalog, core, pg_temp
as $$
declare
  v_person_id uuid;
begin
  v_person_id := core.self_person_id_for_legacy_app_user(new.user_id);
  if v_person_id is null then
    raise exception 'legacy_profile_self_person_missing';
  end if;

  insert into core.person_profiles(
    person_id,display_name,locale,time_zone,avatar_key,profile_photo_path,
    created_at_utc,updated_at_utc
  )
  values(
    v_person_id,new.display_name,new.locale,new.time_zone,new.avatar_key,
    new.profile_photo_path,new.created_at_utc,new.updated_at_utc
  )
  on conflict(person_id) do update set
    display_name=excluded.display_name,
    locale=excluded.locale,
    time_zone=excluded.time_zone,
    avatar_key=excluded.avatar_key,
    profile_photo_path=excluded.profile_photo_path,
    updated_at_utc=excluded.updated_at_utc;
  return new;
end
$$;

-- Legacy healthcare writers may still send only *_user_id. Resolve Person via
-- the explicit bridge instead of copying the AppUser UUID into a Person FK.
create or replace function core.sync_health_person_id()
returns trigger
language plpgsql
set search_path = pg_catalog, core, pg_temp
as $$;
declare
  v_legacy_user_id uuid;
  v_person_id uuid;
begin
  if tg_table_name='medications' and new.owner_person_id is null then
    v_legacy_user_id := new.owner_user_id;
  elsif tg_table_name in ('treatment_plans','dose_occurrences','care_events')
        and new.patient_person_id is null then
    v_legacy_user_id := new.patient_user_id;
  elsif tg_table_name in ('women_calendar_profiles','women_calendar_episodes','women_calendar_daily_logs')
        and new.owner_person_id is null then
    v_legacy_user_id := new.owner_user_id;
  elsif tg_table_name='women_calendar_support_actions'
        and new.patient_person_id is null then
    v_legacy_user_id := new.patient_user_id;
  else
    return new;
  end if;

  if v_legacy_user_id is null then
    raise exception 'legacy_health_owner_user_missing';
  end if;

  v_person_id := core.self_person_id_for_legacy_app_user(v_legacy_user_id);
  if v_person_id is null then
    raise exception 'legacy_health_self_person_missing';
  end if;

  if tg_table_name='medications' then
    new.owner_person_id := v_person_id;
  elsif tg_table_name in ('treatment_plans','dose_occurrences','care_events') then
    new.patient_person_id := v_person_id;
  elsif tg_table_name in ('women_calendar_profiles','women_calendar_episodes','women_calendar_daily_logs') then
    new.owner_person_id := v_person_id;
  elsif tg_table_name='women_calendar_support_actions' then
    new.patient_person_id := v_person_id;
  end if;
  return new;
end
$$;

-- Care grants must authorize the mapped caregiver Account against the mapped
-- patient Person. Using legacy user UUIDs here would silently break isolation as
-- soon as provider identities are decoupled.
create or replace function security.sync_legacy_care_access()
returns trigger
language plpgsql
set search_path = pg_catalog, security, identity, core, lifemate, pg_temp
as $$;
declare
  v_grant_id uuid;
  v_patient_person_id uuid;
  v_caregiver_account_id uuid;
begin
  v_patient_person_id := core.self_person_id_for_legacy_app_user(new.patient_user_id);
  v_caregiver_account_id := identity.account_id_for_legacy_app_user(new.caregiver_user_id);

  if v_patient_person_id is null or v_caregiver_account_id is null then
    raise exception 'legacy_care_bridge_missing';
  end if;

  insert into security.access_grants(
    subject_person_id,grantee_account_id,grantor_person_id,
    context_type,context_id,status,starts_at_utc,expires_at_utc,
    revoked_at_utc,created_at_utc,updated_at_utc
  )
  values(
    v_patient_person_id,v_caregiver_account_id,v_patient_person_id,
    'care_relationship',new.id,
    case when new.status='Active' then 'Active' else 'Revoked' end,
    new.created_at_utc,null,
    case when new.status='Active' then null else coalesce(new.revoked_at_utc,now()) end,
    new.created_at_utc,new.updated_at_utc
  )
  on conflict(subject_person_id,grantee_account_id,context_type,context_id)
  do update set
    status=excluded.status,
    revoked_at_utc=excluded.revoked_at_utc,
    updated_at_utc=excluded.updated_at_utc
  returning id into v_grant_id;

  if new.status='Active' then
    insert into security.access_grant_scopes(grant_id,scope)
    select v_grant_id,scope from (values
      ('treatment.medication.read'),('treatment.plan.read'),
      ('treatment.adherence.read'),('care.events.read')
    ) s(scope)
    on conflict do nothing;

    if coalesce(new.can_view_women_calendar,false) then
      insert into security.access_grant_scopes(grant_id,scope)
      values
        (v_grant_id,'women_health.summary.read'),
        (v_grant_id,'women_health.support.write')
      on conflict do nothing;
    else
      delete from security.access_grant_scopes s
      where s.grant_id=v_grant_id
        and s.scope in (
          'women_health.summary.read',
          'women_health.support.write',
          'women_health.daily.read'
        );
    end if;
  else
    delete from security.access_grant_scopes s where s.grant_id=v_grant_id;
  end if;
  return new;
end
$$;
