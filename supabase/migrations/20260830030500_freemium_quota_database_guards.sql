begin;

-- #616: database-level quota guards so direct/import/invitation paths cannot bypass Commerce policy.

create or replace function lifemate.app_user_id_for_self_person(p_person_id uuid)
returns uuid language sql stable security definer
set search_path=pg_catalog,core,identity,pg_temp
as $$
  select a.legacy_app_user_id
  from core.account_person_links l
  join identity.accounts a on a.id=l.account_id
  where l.person_id=p_person_id
    and l.link_type='Self'
    and l.status='Active'
    and a.status='Active'
    and a.legacy_app_user_id is not null
  order by l.created_at_utc asc
  limit 1
$$;

create or replace function commerce.lock_free_quota(p_app_user_id uuid, p_policy_key text)
returns void language plpgsql security definer
set search_path=pg_catalog,identity,commerce,pg_temp
as $$
declare v_account uuid;
begin
  v_account := identity.account_id_for_legacy_app_user(p_app_user_id);
  if v_account is null then
    raise exception using errcode='P0001', message='identity_account_mapping_missing';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_account::text || ':' || p_policy_key, 0));
end $$;

create or replace function lifemate.enforce_medication_free_quota()
returns trigger language plpgsql security definer
set search_path=pg_catalog,lifemate,commerce,pg_temp
as $$
declare v_count integer; v_app_user_id uuid;
begin
  v_app_user_id := coalesce(new.owner_user_id, lifemate.app_user_id_for_self_person(new.owner_person_id));
  if v_app_user_id is null then
    raise exception using errcode='P0001', message='identity_user_mapping_missing';
  end if;
  perform commerce.lock_free_quota(v_app_user_id,'free.medications.max');
  select count(*)::integer into v_count
  from lifemate.medications m
  where m.owner_person_id=new.owner_person_id and m.id<>new.id;
  perform commerce.assert_free_quota(v_app_user_id,'free.medications.max',v_count);
  return new;
end $$;

drop trigger if exists zzz_enforce_medication_free_quota on lifemate.medications;
create trigger zzz_enforce_medication_free_quota
before insert on lifemate.medications
for each row execute function lifemate.enforce_medication_free_quota();

create or replace function lifemate.enforce_appointment_free_quota()
returns trigger language plpgsql security definer
set search_path=pg_catalog,lifemate,commerce,pg_temp
as $$
declare v_count integer; v_app_user_id uuid;
begin
  if new.event_type<>'Appointment' or new.status='Cancelled' or new.scheduled_local_date<current_date then
    return new;
  end if;
  v_app_user_id := coalesce(new.patient_user_id, lifemate.app_user_id_for_self_person(new.patient_person_id));
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

drop trigger if exists zzz_enforce_appointment_free_quota on lifemate.care_events;
create trigger zzz_enforce_appointment_free_quota
before insert or update of event_type,status,scheduled_local_date,patient_user_id,patient_person_id
on lifemate.care_events
for each row execute function lifemate.enforce_appointment_free_quota();

create or replace function lifemate.enforce_care_relationship_free_quota()
returns trigger language plpgsql security definer
set search_path=pg_catalog,lifemate,commerce,pg_temp
as $$
declare v_owner_count integer; v_caregiver_count integer;
begin
  if new.status<>'Active' then return new; end if;
  if new.patient_user_id is null or new.caregiver_user_id is null then
    raise exception using errcode='P0001', message='identity_user_mapping_missing';
  end if;

  perform commerce.lock_free_quota(new.patient_user_id,'free.owner_caregivers.max');
  select count(*)::integer into v_owner_count
  from lifemate.care_relationships r
  where r.patient_person_id=new.patient_person_id and r.status='Active' and r.id<>new.id;
  perform commerce.assert_free_quota(new.patient_user_id,'free.owner_caregivers.max',v_owner_count);

  perform commerce.lock_free_quota(new.caregiver_user_id,'free.caremate_people.max');
  select count(*)::integer into v_caregiver_count
  from lifemate.care_relationships r
  where r.caregiver_person_id=new.caregiver_person_id and r.status='Active' and r.id<>new.id;
  perform commerce.assert_free_quota(new.caregiver_user_id,'free.caremate_people.max',v_caregiver_count);
  return new;
end $$;

drop trigger if exists zzz_enforce_care_relationship_free_quota on lifemate.care_relationships;
create trigger zzz_enforce_care_relationship_free_quota
before insert or update of status,patient_user_id,caregiver_user_id,patient_person_id,caregiver_person_id
on lifemate.care_relationships
for each row execute function lifemate.enforce_care_relationship_free_quota();

revoke all on function lifemate.app_user_id_for_self_person(uuid) from public;
revoke all on function commerce.lock_free_quota(uuid,text) from public;
grant execute on function commerce.lock_free_quota(uuid,text) to lifemate_edge_runtime;
revoke all on function lifemate.enforce_medication_free_quota() from public;
revoke all on function lifemate.enforce_appointment_free_quota() from public;
revoke all on function lifemate.enforce_care_relationship_free_quota() from public;

commit;
