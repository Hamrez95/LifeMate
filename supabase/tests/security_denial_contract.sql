\set ON_ERROR_STOP on
begin;

insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc) values
('81000000-0000-0000-0000-000000000001','denial-subject-a','Active',now(),now()),
('81000000-0000-0000-0000-000000000002','denial-subject-b','Active',now(),now()),
('81000000-0000-0000-0000-000000000003','denial-subject-c','Active',now(),now());

insert into lifemate.user_profiles(id,user_id,display_name,locale,time_zone,created_at_utc,updated_at_utc) values
('81100000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000001','Denial A','fa','Asia/Tehran',now(),now()),
('81100000-0000-0000-0000-000000000002','81000000-0000-0000-0000-000000000002','Denial B','fa','Asia/Tehran',now(),now()),
('81100000-0000-0000-0000-000000000003','81000000-0000-0000-0000-000000000003','Denial C','fa','Asia/Tehran',now(),now());

insert into lifemate.care_relationships(
 id,patient_user_id,caregiver_user_id,status,
 patient_consent_version,patient_consented_at_utc,
 caregiver_consent_version,caregiver_consented_at_utc,
 created_at_utc,updated_at_utc,can_view_women_calendar)
values(
 '84000000-0000-0000-0000-000000000001',
 '81000000-0000-0000-0000-000000000001',
 '81000000-0000-0000-0000-000000000002','Active',
 'denial-p-v1',now(),'denial-c-v1',now(),now(),now(),false);

do $$
begin
  -- Entitlement alone cannot cross Person boundaries without a scope/consent.
  if security.can_access_person_feature(
    '81000000-0000-0000-0000-000000000003',
    '81000000-0000-0000-0000-000000000001',
    'treatment.adherence.read','care.basic','care_sharing')
  then raise exception 'unrelated account obtained cross-person access'; end if;

  -- B has all three layers and is allowed.
  if not security.can_access_person_feature(
    '81000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000001',
    'treatment.adherence.read','care.basic','care_sharing')
  then raise exception 'valid caregiver unexpectedly denied'; end if;

  -- Women-health permission was not granted by the relationship.
  if security.has_scope(
    '81000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000001',
    'women_health.summary.read')
  then raise exception 'women summary leaked without explicit permission'; end if;

  -- There is deliberately no generic private-note sharing scope.
  if exists(select 1 from security.scope_catalog where scope='women_health.private_notes.read')
  then raise exception 'private-note sharing scope must not exist'; end if;
end $$;

-- Consent without required commercial capability must deny.
update commerce.entitlements e
set status='Revoked',updated_at_utc=now()
from commerce.features f
where e.feature_id=f.id
  and e.grantee_account_id='81000000-0000-0000-0000-000000000002'
  and f.code='care.basic'
  and e.status='Active';

do $$
begin
  if security.can_access_person_feature(
    '81000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000001',
    'treatment.adherence.read','care.basic','care_sharing')
  then raise exception 'consent+scope bypassed missing entitlement'; end if;
end $$;

update commerce.entitlements e
set status='Active',updated_at_utc=now()
from commerce.features f
where e.feature_id=f.id
  and e.grantee_account_id='81000000-0000-0000-0000-000000000002'
  and f.code='care.basic';

-- Entitlement + scope without current consent must deny.
update consent.consent_records
set status='Revoked',revoked_at_utc=now(),updated_at_utc=now()
where subject_person_id='81000000-0000-0000-0000-000000000001'
  and purpose='care_sharing';

do $$
begin
  if security.can_access_person_feature(
    '81000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000001',
    'treatment.adherence.read','care.basic','care_sharing')
  then raise exception 'entitlement+scope bypassed revoked consent'; end if;
end $$;

-- Re-grant via legacy relationship transition, then expire grant by time window.
update lifemate.care_relationships set status='Revoked',revoked_by_user_id='81000000-0000-0000-0000-000000000001',revoked_at_utc=now(),updated_at_utc=now()
where id='84000000-0000-0000-0000-000000000001';
update lifemate.care_relationships set status='Active',revoked_by_user_id=null,revoked_at_utc=null,updated_at_utc=now()
where id='84000000-0000-0000-0000-000000000001';
update security.access_grants
set expires_at_utc=now()-interval '1 second'
where context_type='care_relationship' and context_id='84000000-0000-0000-0000-000000000001';

do $$
begin
  if security.has_scope(
    '81000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000001',
    'treatment.adherence.read')
  then raise exception 'expired grant remained active'; end if;
end $$;

-- Account deletion must revoke current legacy relationship access immediately.
update security.access_grants set expires_at_utc=null
where context_type='care_relationship' and context_id='84000000-0000-0000-0000-000000000001';
select identity.request_account_deletion('81000000-0000-0000-0000-000000000001');

do $$
begin
  if exists(select 1 from lifemate.care_relationships where patient_user_id='81000000-0000-0000-0000-000000000001' and status='Active')
  then raise exception 'account deletion left active caregiver relationship'; end if;
  if exists(select 1 from identity.external_identities where account_id='81000000-0000-0000-0000-000000000001' and status='Active')
  then raise exception 'account deletion left active external identity'; end if;
  if exists(select 1 from ecosystem.app_enrollments where account_id='81000000-0000-0000-0000-000000000001' and status='Active')
  then raise exception 'account deletion left active enrollment'; end if;
end $$;

-- Restricted-source commercial paths are fail-closed independent of consent.
do $$
begin
  if analytics.commercial_export_allowed_reviewed('HealthConnect','Adult',true,true,true,true)
  then raise exception 'HealthConnect entered commercial export'; end if;
  if analytics.commercial_export_allowed_reviewed('FirstPartyUserInput','Child',true,true,true,true)
  then raise exception 'child data entered commercial export'; end if;
end $$;

rollback;
