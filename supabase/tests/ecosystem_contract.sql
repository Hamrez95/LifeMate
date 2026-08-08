\set ON_ERROR_STOP on
begin;

-- Two existing-style login accounts. Compatibility triggers must build the
-- ecosystem Account/Person/Enrollment/Free-Entitlement records.
insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc) values
('10000000-0000-0000-0000-000000000001','contract-subject-a','Active',now(),now()),
('10000000-0000-0000-0000-000000000002','contract-subject-b','Active',now(),now());

insert into lifemate.user_profiles(
 id,user_id,display_name,locale,time_zone,created_at_utc,updated_at_utc)
values
('11000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Contract A','fa','Asia/Tehran',now(),now()),
('11000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Contract B','fa','Asia/Tehran',now(),now());

-- Child/dependent Person has no account and can still own treatment data.
insert into core.persons(id,status,subject_category,created_at_utc,updated_at_utc)
values('20000000-0000-0000-0000-000000000001','Active','Child',now(),now());
insert into core.person_profiles(person_id,display_name,locale,time_zone)
values('20000000-0000-0000-0000-000000000001','Contract Child','fa','Asia/Tehran');
insert into core.account_person_links(account_id,person_id,link_type,status)
values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Guardian','Active');

insert into lifemate.medications(
 id,owner_user_id,owner_person_id,name,version,created_at_utc,updated_at_utc)
values(
 '30000000-0000-0000-0000-000000000001',null,
 '20000000-0000-0000-0000-000000000001','Contract medication',1,now(),now());

-- Current care relationship writes must create grant + scopes + versioned consent.
insert into lifemate.care_relationships(
 id,patient_user_id,caregiver_user_id,status,
 patient_consent_version,patient_consented_at_utc,
 caregiver_consent_version,caregiver_consented_at_utc,
 created_at_utc,updated_at_utc,can_view_women_calendar)
values(
 '40000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000002','Active',
 'contract-patient-v1',now(),'contract-caregiver-v1',now(),now(),now(),false);

do $$
begin
  if not exists(select 1 from identity.accounts where id='10000000-0000-0000-0000-000000000001') then raise exception 'account sync failed'; end if;
  if not exists(select 1 from core.persons where id='10000000-0000-0000-0000-000000000001') then raise exception 'self person sync failed'; end if;
  if (select count(*) from ecosystem.app_enrollments where account_id='10000000-0000-0000-0000-000000000001' and status='Active') < 2 then raise exception 'multi-app enrollment failed'; end if;
  if not commerce.has_entitlement('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','treatment.basic') then raise exception 'free entitlement failed'; end if;
  if not security.has_scope('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','treatment.adherence.read') then raise exception 'care scope sync failed'; end if;
  if security.has_scope('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','women_health.summary.read') then raise exception 'women scope granted without permission'; end if;
  if not exists(select 1 from consent.consent_records where subject_person_id='10000000-0000-0000-0000-000000000001' and purpose='care_sharing' and status='Granted') then raise exception 'care consent sync failed'; end if;
end $$;

update lifemate.care_relationships
set can_view_women_calendar=true,updated_at_utc=now()
where id='40000000-0000-0000-0000-000000000001';

do $$
begin
  if not security.has_scope('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','women_health.summary.read') then raise exception 'women summary scope missing'; end if;
  if not security.has_scope('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','women_health.support.write') then raise exception 'women support scope missing'; end if;
end $$;

-- Cross-person capability requires entitlement + scope + current consent.
do $$
begin
  if not security.can_access_person_feature(
    '10000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'treatment.adherence.read','care.basic','care_sharing')
  then raise exception 'combined care policy should allow'; end if;
end $$;

-- Revoked consent denies even while a scope and entitlement exist.
update consent.consent_records
set status='Revoked',revoked_at_utc=now(),updated_at_utc=now()
where subject_person_id='10000000-0000-0000-0000-000000000001'
  and purpose='care_sharing';

do $$
begin
  if security.can_access_person_feature(
    '10000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'treatment.adherence.read','care.basic','care_sharing')
  then raise exception 'revoked consent must deny'; end if;
end $$;

-- Paid/trial/revoked/expired capability behavior.
insert into commerce.features(code,description) values('contract.paid','Contract paid feature');
insert into commerce.entitlements(
 grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,starts_at_utc,expires_at_utc)
select
 '10000000-0000-0000-0000-000000000001',
 '20000000-0000-0000-0000-000000000001',id,'TRIAL','contract-trial','Active',now(),now()+interval '1 day'
from commerce.features where code='contract.paid';

do $$
begin
  if not commerce.has_entitlement('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','contract.paid') then raise exception 'trial entitlement failed'; end if;
end $$;
update commerce.entitlements set status='Expired',expires_at_utc=now()-interval '1 second'
where source_key='contract-trial';
do $$
begin
  if commerce.has_entitlement('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','contract.paid') then raise exception 'expired entitlement allowed'; end if;
end $$;

-- Restricted-source and child commercial policy must remain hard-denied.
do $$
begin
  if analytics.commercial_export_allowed_reviewed('HealthConnect','Adult',true,true,true,true) then raise exception 'HealthConnect commercial export allowed'; end if;
  if analytics.commercial_export_allowed_reviewed('FirstPartyUserInput','Child',true,true,true,true) then raise exception 'child commercial export allowed'; end if;
  if analytics.commercial_export_allowed_reviewed('FirstPartyUserInput','Adult',true,true,true,true) then raise exception 'global commercial kill switch ignored'; end if;
end $$;

-- Relationship revocation must immediately remove all scopes and revoke consent.
update lifemate.care_relationships
set status='Revoked',revoked_by_user_id='10000000-0000-0000-0000-000000000001',revoked_at_utc=now(),updated_at_utc=now()
where id='40000000-0000-0000-0000-000000000001';
do $$
begin
  if security.has_scope('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','treatment.adherence.read') then raise exception 'revoked relationship kept scope'; end if;
  if exists(select 1 from consent.consent_records where subject_person_id='10000000-0000-0000-0000-000000000001' and purpose='care_sharing' and status='Granted') then raise exception 'revoked relationship kept consent'; end if;
end $$;

-- Account deletion flow blocks the legacy API identity and queues asynchronous work.
select identity.request_account_deletion('10000000-0000-0000-0000-000000000002');
do $$
begin
  if exists(select 1 from lifemate.app_users where id='10000000-0000-0000-0000-000000000002' and status='Active') then raise exception 'deletion did not disable legacy API account'; end if;
  if (select count(*) from integration.outbox_messages where aggregate_id='10000000-0000-0000-0000-000000000002') < 2 then raise exception 'deletion outbox missing'; end if;
end $$;

rollback;
