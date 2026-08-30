begin;

-- #616: database-level quota guards so direct/import/invitation paths cannot bypass Commerce policy.

create or replace function lifemate.enforce_medication_free_quota()
returns trigger language plpgsql security definer
set search_path=pg_catalog,lifemate,commerce,pg_temp
as $$
declare v_count integer;
begin
  if new.owner_user_id is null then
    raise exception using errcode='P0001', message='identity_user_mapping_missing';
  end if;
  select count(*)::integer into v_count
  from lifemate.medications m
  where m.owner_user_id=new.owner_user_id and m.id<>new.id;
  perform commerce.assert_free_quota(new.owner_user_id,'free.medications.max',v_count);
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
declare v_count integer;
begin
  if new.event_type<>'Appointment' or new.status='Cancelled' or new.scheduled_local_date<current_date then
    return new;
  end if;
  if new.patient_user_id is null then
    raise exception using errcode='P0001', message='identity_user_mapping_missing';
  end if;
  select count(*)::integer into v_count
  from lifemate.care_events e
  where e.patient_user_id=new.patient_user_id
    and e.id<>new.id
    and e.event_type='Appointment'
    and e.status<>'Cancelled'
    and e.scheduled_local_date>=current_date;
  perform commerce.assert_free_quota(new.patient_user_id,'free.visits.max',v_count);
  return new;
end $$;

drop trigger if exists zzz_enforce_appointment_free_quota on lifemate.care_events;
create trigger zzz_enforce_appointment_free_quota
before insert or update of event_type,status,scheduled_local_date,patient_user_id
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

  select count(*)::integer into v_owner_count
  from lifemate.care_relationships r
  where r.patient_user_id=new.patient_user_id and r.status='Active' and r.id<>new.id;
  perform commerce.assert_free_quota(new.patient_user_id,'free.owner_caregivers.max',v_owner_count);

  select count(*)::integer into v_caregiver_count
  from lifemate.care_relationships r
  where r.caregiver_user_id=new.caregiver_user_id and r.status='Active' and r.id<>new.id;
  perform commerce.assert_free_quota(new.caregiver_user_id,'free.caremate_people.max',v_caregiver_count);
  return new;
end $$;

drop trigger if exists zzz_enforce_care_relationship_free_quota on lifemate.care_relationships;
create trigger zzz_enforce_care_relationship_free_quota
before insert or update of status,patient_user_id,caregiver_user_id
on lifemate.care_relationships
for each row execute function lifemate.enforce_care_relationship_free_quota();

revoke all on function lifemate.enforce_medication_free_quota() from public;
revoke all on function lifemate.enforce_appointment_free_quota() from public;
revoke all on function lifemate.enforce_care_relationship_free_quota() from public;

commit;
