-- Complete the compatibility bridge so health data can belong to a Person
-- without requiring that Person to own a login account.

-- Legacy account/user ownership remains optional compatibility metadata.
alter table lifemate.medications alter column owner_user_id drop not null;
alter table lifemate.treatment_plans alter column patient_user_id drop not null;
alter table lifemate.dose_occurrences alter column patient_user_id drop not null;
alter table lifemate.care_events alter column patient_user_id drop not null;

-- Person is the authoritative data subject for treatment/care records.
alter table lifemate.medications alter column owner_person_id set not null;
alter table lifemate.treatment_plans alter column patient_person_id set not null;
alter table lifemate.dose_occurrences alter column patient_person_id set not null;
alter table lifemate.care_events alter column patient_person_id set not null;

create unique index if not exists uq_care_events_person_client_request
  on lifemate.care_events(patient_person_id,client_request_id);

-- The compatibility trigger fills Person only when a legacy writer did not
-- already supply an explicit Person. This allows future child/dependent data.
create or replace function core.sync_health_person_id()
returns trigger
language plpgsql
set search_path = core, pg_temp
as $$
begin
  if tg_table_name='medications' then
    if new.owner_person_id is null then new.owner_person_id := new.owner_user_id; end if;
  elsif tg_table_name='treatment_plans' then
    if new.patient_person_id is null then new.patient_person_id := new.patient_user_id; end if;
  elsif tg_table_name='dose_occurrences' then
    if new.patient_person_id is null then new.patient_person_id := new.patient_user_id; end if;
  elsif tg_table_name='care_events' then
    if new.patient_person_id is null then new.patient_person_id := new.patient_user_id; end if;
  elsif tg_table_name in ('women_calendar_profiles','women_calendar_episodes','women_calendar_daily_logs') then
    if new.owner_person_id is null then new.owner_person_id := new.owner_user_id; end if;
  elsif tg_table_name='women_calendar_support_actions' then
    if new.patient_person_id is null then new.patient_person_id := new.patient_user_id; end if;
  end if;
  return new;
end
$$;

-- Replace care access trigger using an unambiguous local variable.
create or replace function security.sync_legacy_care_access()
returns trigger
language plpgsql
set search_path = security, lifemate, pg_temp
as $$
declare v_grant_id uuid;
begin
  insert into security.access_grants(
    subject_person_id,grantee_account_id,grantor_person_id,
    context_type,context_id,status,starts_at_utc,expires_at_utc,revoked_at_utc,created_at_utc,updated_at_utc)
  values(
    new.patient_user_id,new.caregiver_user_id,new.patient_user_id,
    'care_relationship',new.id,
    case when new.status='Active' then 'Active' else 'Revoked' end,
    new.created_at_utc,null,
    case when new.status='Active' then null else coalesce(new.revoked_at_utc,now()) end,
    new.created_at_utc,new.updated_at_utc)
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
      values(v_grant_id,'women_health.summary.read'),(v_grant_id,'women_health.support.write')
      on conflict do nothing;
    else
      delete from security.access_grant_scopes s
      where s.grant_id=v_grant_id
        and s.scope in ('women_health.summary.read','women_health.support.write','women_health.daily.read');
    end if;
  else
    delete from security.access_grant_scopes s where s.grant_id=v_grant_id;
  end if;
  return new;
end
$$;

-- Existing women-summary relationships already allowed support actions under
-- the old boolean, so the compatibility scope set must preserve that behavior.
insert into security.access_grant_scopes(grant_id,scope)
select g.id,'women_health.support.write'
from security.access_grants g
join lifemate.care_relationships r on r.id=g.context_id
where g.context_type='care_relationship'
  and g.status='Active'
  and r.status='Active'
  and coalesce(r.can_view_women_calendar,false)=true
on conflict do nothing;

-- Never leave default PUBLIC function execution as an accidental alternate path.
revoke execute on all functions in schema identity from public;
revoke execute on all functions in schema security from public;
revoke execute on all functions in schema commerce from public;
revoke execute on all functions in schema analytics from public;

comment on column lifemate.medications.owner_user_id is
'Legacy compatibility account/self-person link. New ownership authority is owner_person_id.';
comment on column lifemate.treatment_plans.patient_user_id is
'Legacy compatibility account/self-person link. New ownership authority is patient_person_id.';
comment on column lifemate.dose_occurrences.patient_user_id is
'Legacy compatibility account/self-person link. New ownership authority is patient_person_id.';
comment on column lifemate.care_events.patient_user_id is
'Legacy compatibility account/self-person link. New ownership authority is patient_person_id.';
