\set ON_ERROR_STOP on
begin;

-- This contract needs two simultaneously active caregiver contexts for one
-- Person so it can prove consent cannot be borrowed across relationships.
-- Keep the production quota guard intact; widen only this rolled-back test
-- fixture instead of inventing a subscription, purchase, or payment.
update commerce.catalog_policies cp
set value_json='2'::jsonb,
    updated_at_utc=now()
from commerce.products p
where p.id=cp.product_id
  and p.code='wellmate-caremate'
  and cp.policy_key='free.owner_caregivers.max'
  and cp.status='Active';

insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc) values
('71000000-0000-0000-0000-000000000001','context-subject-a','Active',now(),now()),
('71000000-0000-0000-0000-000000000002','context-subject-b','Active',now(),now()),
('71000000-0000-0000-0000-000000000003','context-subject-c','Active',now(),now());

insert into lifemate.care_relationships(
  id,patient_user_id,caregiver_user_id,status,
  patient_consent_version,patient_consented_at_utc,
  caregiver_consent_version,caregiver_consented_at_utc,
  created_at_utc,updated_at_utc,can_view_women_calendar)
values
('74000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000002','Active','context-v1',now(),'context-v1',now(),now(),now(),false),
('74000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000003','Active','context-v1',now(),'context-v1',now(),now(),now(),false);

-- Revoke only caregiver B's relationship-specific consent. C still has a
-- different active consent for the same Person. B must not be able to borrow it.
update consent.consent_records
set status='Revoked',revoked_at_utc=now(),updated_at_utc=now()
where scope_key='care_relationship:74000000-0000-0000-0000-000000000001';

do $$
begin
  if security.can_access_person_feature(
    '71000000-0000-0000-0000-000000000002',
    '71000000-0000-0000-0000-000000000001',
    'treatment.adherence.read','care.basic','care_sharing')
  then raise exception 'relationship-specific revoked consent was bypassed'; end if;

  if not security.can_access_person_feature(
    '71000000-0000-0000-0000-000000000003',
    '71000000-0000-0000-0000-000000000001',
    'treatment.adherence.read','care.basic','care_sharing')
  then raise exception 'valid context-specific consent was unexpectedly denied'; end if;
end $$;

rollback;
