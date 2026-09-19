\set ON_ERROR_STOP on
begin;

insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc) values
('71000000-0000-0000-0000-000000000001','context-subject-a','Active',now(),now()),
('71000000-0000-0000-0000-000000000002','context-subject-b','Active',now(),now()),
('71000000-0000-0000-0000-000000000003','context-subject-c','Active',now(),now());

-- This contract needs two simultaneous caregiver contexts. Make the synthetic
-- patient premium so the unrelated freemium relationship quota cannot mask the
-- consent-isolation assertion under test.
insert into commerce.subscriptions(
  payer_account_id,owner_account_id,product_id,plan_id,
  provider,provider_reference_hash,status,starts_at_utc,current_period_end_utc
)
select
  a.id,a.id,p.id,pl.id,
  'ContractTest','consent-context-contract','Active',
  now()-interval '1 minute',now()+interval '1 day'
from identity.accounts a
join commerce.products p on p.code='wellmate-caremate'
join lateral (
  select id from commerce.plans
  where product_id=p.id and status='Active'
  order by code
  limit 1
) pl on true
where a.legacy_app_user_id='71000000-0000-0000-0000-000000000001'::uuid;

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
