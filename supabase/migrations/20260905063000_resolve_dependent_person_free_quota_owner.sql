begin;

-- Person-authoritative healthcare writes no longer persist legacy ownership
-- columns. Free-tier database guards therefore need a safe Account bridge for
-- dependent Persons as well as Self Persons. Prefer the unique active Self
-- Account. For a dependent Person, resolve only when exactly one active
-- managing Account (Parent/Guardian/LegalGuardian/Proxy) has a legacy AppUser
-- bridge. Multiple managers are intentionally ambiguous and fail closed.
create or replace function lifemate.app_user_id_for_quota_person(p_person_id uuid)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,core,identity,pg_temp
as $$
  with candidates as (
    select distinct
      l.account_id,
      a.legacy_app_user_id,
      case when l.link_type='Self' then 0 else 1 end as priority
    from core.account_person_links l
    join identity.accounts a on a.id=l.account_id
    where l.person_id=p_person_id
      and l.status='Active'
      and l.link_type in ('Self','Parent','Guardian','LegalGuardian','Proxy')
      and a.status='Active'
      and a.legacy_app_user_id is not null
  ), preferred as (
    select c.*
    from candidates c
    where c.priority=(select min(priority) from candidates)
  )
  select case
    when count(*)=1 then min(legacy_app_user_id)
    else null::uuid
  end
  from preferred
$$;

create or replace function lifemate.enforce_medication_free_quota()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,lifemate,commerce,pg_temp
as $$
declare
  v_count integer;
  v_app_user_id uuid;
begin
  v_app_user_id := coalesce(
    new.owner_user_id,
    lifemate.app_user_id_for_quota_person(new.owner_person_id)
  );
  if v_app_user_id is null then
    raise exception using errcode='P0001', message='identity_user_mapping_missing';
  end if;

  perform commerce.lock_free_quota(v_app_user_id,'free.medications.max');
  select count(*)::integer into v_count
  from lifemate.medications m
  where m.owner_person_id=new.owner_person_id
    and m.id<>new.id;
  perform commerce.assert_free_quota(
    v_app_user_id,
    'free.medications.max',
    v_count
  );
  return new;
end $$;

create or replace function lifemate.enforce_appointment_free_quota()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,lifemate,commerce,pg_temp
as $$
declare
  v_count integer;
  v_app_user_id uuid;
begin
  if new.event_type<>'Appointment'
     or new.status='Cancelled'
     or new.scheduled_local_date<current_date then
    return new;
  end if;

  v_app_user_id := coalesce(
    new.patient_user_id,
    lifemate.app_user_id_for_quota_person(new.patient_person_id)
  );
  if v_app_user_id is null then
    raise exception using errcode='P0001', message='identity_user_mapping_missing';
  end if;

  perform commerce.lock_free_quota(v_app_user_id,'free.visits.max');
  select count(*)::integer into v_count
  from lifemate.care_events e
  where e.patient_person_id=new.patient_person_id
    and e.id<>new.id
    and e.event_type='Appointment'
    and e.status<>'Cancelled'
    and e.scheduled_local_date>=current_date;
  perform commerce.assert_free_quota(v_app_user_id,'free.visits.max',v_count);
  return new;
end $$;

revoke all on function lifemate.app_user_id_for_quota_person(uuid) from public;
revoke all on function lifemate.enforce_medication_free_quota() from public;
revoke all on function lifemate.enforce_appointment_free_quota() from public;

commit;
