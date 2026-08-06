\set ON_ERROR_STOP on

-- Required psql variables:
-- accounts, persons, relationships, plans, doses, adherence, women_logs, audits
-- Full target example:
--   accounts=1000000 persons=1200000 relationships=2000000 plans=250000
--   doses=5000000 adherence=5000000 women_logs=2000000 audits=2000000

do $$
begin
  if current_database() !~ '^lifemate_benchmark' then
    raise exception 'Refusing benchmark data generation outside lifemate_benchmark* database';
  end if;
end $$;

set synchronous_commit = off;
set maintenance_work_mem = '1GB';

alter table lifemate.app_users disable trigger user;
alter table lifemate.user_profiles disable trigger user;
alter table lifemate.care_relationships disable trigger user;

insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
select md5('acct-'||g)::uuid,'bench-subject-'||g,'Active',now(),now()
from generate_series(1,:accounts) g;

insert into identity.accounts(id,legacy_app_user_id,status,created_at_utc,updated_at_utc)
select md5('acct-'||g)::uuid,md5('acct-'||g)::uuid,'Active',now(),now()
from generate_series(1,:accounts) g;

insert into identity.external_identities(account_id,provider,issuer,provider_subject,status,created_at_utc)
select md5('acct-'||g)::uuid,'supabase_auth','benchmark','bench-subject-'||g,'Active',now()
from generate_series(1,:accounts) g;

insert into core.persons(id,status,subject_category,created_at_utc,updated_at_utc)
select case when g<=:accounts then md5('acct-'||g)::uuid else md5('dependent-'||g)::uuid end,
       'Active',case when g<=:accounts then 'Adult' else 'Dependent' end,now(),now()
from generate_series(1,:persons) g;

insert into core.person_profiles(person_id,display_name,locale,time_zone,created_at_utc,updated_at_utc)
select case when g<=:accounts then md5('acct-'||g)::uuid else md5('dependent-'||g)::uuid end,
       'Benchmark Person '||g,'fa','Asia/Tehran',now(),now()
from generate_series(1,:persons) g;

insert into core.account_person_links(account_id,person_id,link_type,status,created_at_utc)
select md5('acct-'||g)::uuid,md5('acct-'||g)::uuid,'Self','Active',now()
from generate_series(1,:accounts) g;

insert into lifemate.user_profiles(id,user_id,display_name,locale,time_zone,created_at_utc,updated_at_utc)
select md5('profile-'||g)::uuid,md5('acct-'||g)::uuid,'Benchmark User '||g,'fa','Asia/Tehran',now(),now()
from generate_series(1,:accounts) g;

insert into ecosystem.app_enrollments(account_id,application_id,status,enrolled_at_utc)
select md5('acct-'||g)::uuid,a.id,'Active',now()
from generate_series(1,:accounts) g
cross join ecosystem.applications a
where a.code in ('wellmate','caremate');

insert into commerce.entitlements(grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,starts_at_utc)
select md5('acct-'||g)::uuid,null,f.id,'FREE','benchmark:care.basic','Active',now()
from generate_series(1,:accounts) g
cross join commerce.features f
where f.code='care.basic';

with rel as (
  select g,
         ((g-1)%:accounts)+1 as patient_num,
         (((g-1)/:accounts)::bigint)+1 as rel_offset
  from generate_series(1,:relationships) g
), shaped as (
  select g,patient_num,
         ((patient_num-1+rel_offset)%:accounts)+1 as caregiver_num
  from rel
)
insert into lifemate.care_relationships(
  id,patient_user_id,caregiver_user_id,status,
  patient_consent_version,patient_consented_at_utc,
  caregiver_consent_version,caregiver_consented_at_utc,
  created_at_utc,updated_at_utc,can_view_women_calendar)
select md5('rel-'||g)::uuid,
       md5('acct-'||patient_num)::uuid,
       md5('acct-'||caregiver_num)::uuid,
       'Active','bench-v1',now(),'bench-v1',now(),now(),now(),(g%20=0)
from shaped;

with rel as (
  select g,
         ((g-1)%:accounts)+1 as patient_num,
         (((g-1)/:accounts)::bigint)+1 as rel_offset
  from generate_series(1,:relationships) g
), shaped as (
  select g,patient_num,
         ((patient_num-1+rel_offset)%:accounts)+1 as caregiver_num
  from rel
)
insert into security.access_grants(
  id,subject_person_id,grantee_account_id,grantor_person_id,
  context_type,context_id,status,starts_at_utc,created_at_utc,updated_at_utc)
select md5('grant-'||g)::uuid,
       md5('acct-'||patient_num)::uuid,
       md5('acct-'||caregiver_num)::uuid,
       md5('acct-'||patient_num)::uuid,
       'care_relationship',md5('rel-'||g)::uuid,'Active',now(),now(),now()
from shaped;

insert into security.access_grant_scopes(grant_id,scope)
select md5('grant-'||g)::uuid,'treatment.adherence.read'
from generate_series(1,:relationships) g;

insert into consent.consent_documents(id,purpose,version,jurisdiction,title,status,effective_at_utc)
values(md5('benchmark-consent-document')::uuid,'care_sharing','bench-v1','*','Benchmark care consent','Active',now())
on conflict(purpose,version,jurisdiction) do nothing;

with rel as (
  select g,((g-1)%:accounts)+1 as patient_num
  from generate_series(1,:relationships) g
)
insert into consent.consent_records(
  id,subject_person_id,actor_account_id,document_id,purpose,scope_key,
  data_categories,jurisdiction,source,status,granted_at_utc,created_at_utc,updated_at_utc)
select md5('consent-'||g)::uuid,
       md5('acct-'||patient_num)::uuid,md5('acct-'||patient_num)::uuid,
       md5('benchmark-consent-document')::uuid,'care_sharing','care_relationship:'||md5('rel-'||g)::uuid::text,
       array['treatment']::character varying[],'*','benchmark','Granted',now(),now(),now()
from rel;

insert into lifemate.medications(
  id,owner_user_id,owner_person_id,name,version,created_at_utc,updated_at_utc)
select md5('med-'||g)::uuid,md5('acct-'||(((g-1)%:accounts)+1))::uuid,
       md5('acct-'||(((g-1)%:accounts)+1))::uuid,'Benchmark medication '||g,1,now(),now()
from generate_series(1,:plans) g;

insert into lifemate.treatment_plans(
  id,patient_user_id,patient_person_id,medication_id,dose_text,start_date,end_date,
  time_zone,status,version,created_at_utc,updated_at_utc)
select md5('plan-'||g)::uuid,md5('acct-'||(((g-1)%:accounts)+1))::uuid,
       md5('acct-'||(((g-1)%:accounts)+1))::uuid,md5('med-'||g)::uuid,
       '1 tablet',current_date-30,null,'Asia/Tehran','Active',1,now(),now()
from generate_series(1,:plans) g;

insert into lifemate.treatment_schedules(id,treatment_plan_id,day_of_week,local_time,created_at_utc)
select md5('schedule-'||g)::uuid,md5('plan-'||g)::uuid,'monday','08:00'::time,now()
from generate_series(1,:plans) g;

with d as (
  select g,((g-1)%:plans)+1 as plan_num,((g-1)/:plans)::bigint as slot
  from generate_series(1,:doses) g
)
insert into lifemate.dose_occurrences(
  id,patient_user_id,patient_person_id,treatment_plan_id,treatment_schedule_id,
  scheduled_at_utc,scheduled_local_date,scheduled_local_time,time_zone,status,
  responded_at_utc,version,created_at_utc,updated_at_utc)
select md5('dose-'||g)::uuid,
       md5('acct-'||(((plan_num-1)%:accounts)+1))::uuid,
       md5('acct-'||(((plan_num-1)%:accounts)+1))::uuid,
       md5('plan-'||plan_num)::uuid,md5('schedule-'||plan_num)::uuid,
       date_trunc('day',now()) + slot*interval '1 day' + interval '8 hour',
       current_date + slot::integer,'08:00'::time,'Asia/Tehran',
       case when g%5=0 then 'Missed' when g%3=0 then 'Taken' else 'Scheduled' end,
       case when g%3=0 then now() else null end,1,now(),now()
from d;

with a as (
  select g,((g-1)%:doses)+1 as dose_num,((g-1)%:accounts)+1 as actor_num
  from generate_series(1,:adherence) g
)
insert into lifemate.dose_adherence_events(
  id,occurrence_id,actor_user_id,client_request_id,event_type,
  previous_status,resulting_status,occurred_at_utc,recorded_at_utc)
select md5('adherence-'||g)::uuid,md5('dose-'||dose_num)::uuid,
       md5('acct-'||actor_num)::uuid,md5('adherence-request-'||g)::uuid,
       'Taken','Scheduled','Taken',now(),now()
from a;

with w as (
  select g,((g-1)%:accounts)+1 as owner_num,((g-1)/:accounts)::bigint as slot
  from generate_series(1,:women_logs) g
)
insert into lifemate.women_calendar_daily_logs(
  id,owner_user_id,owner_person_id,logged_on,mood,energy_level,pain_level,
  symptoms,private_notes,share_summary_with_companion,version,created_at_utc,updated_at_utc)
select md5('women-log-'||g)::uuid,md5('acct-'||owner_num)::uuid,md5('acct-'||owner_num)::uuid,
       current_date-(slot%365)::integer,'Neutral',3,1,'{}'::character varying[],null,(g%10=0),1,now(),now()
from w;

with a as (
  select g,((g-1)%:accounts)+1 as actor_num,((g-1)%:doses)+1 as resource_num
  from generate_series(1,:audits) g
)
insert into lifemate.audit_logs(id,actor_user_id,action,resource_type,resource_id,metadata_json,created_at_utc)
select md5('audit-'||g)::uuid,md5('acct-'||actor_num)::uuid,'dose.read','dose_occurrence',
       md5('dose-'||resource_num)::uuid,null,now()-(g%100000)*interval '1 second'
from a;

insert into care.daily_adherence_summary(person_id,summary_date,scheduled_count,taken_count,missed_count,late_count,projection_version,rebuilt_at_utc)
select md5('acct-'||g)::uuid,current_date,8,6,1,1,1,now()
from generate_series(1,:accounts) g;

alter table lifemate.app_users enable trigger user;
alter table lifemate.user_profiles enable trigger user;
alter table lifemate.care_relationships enable trigger user;

analyze identity.accounts;
analyze identity.external_identities;
analyze core.account_person_links;
analyze lifemate.care_relationships;
analyze security.access_grants;
analyze security.access_grant_scopes;
analyze consent.consent_records;
analyze commerce.entitlements;
analyze lifemate.medications;
analyze lifemate.treatment_plans;
analyze lifemate.dose_occurrences;
analyze lifemate.dose_adherence_events;
analyze lifemate.women_calendar_daily_logs;
analyze lifemate.audit_logs;
analyze care.daily_adherence_summary;
