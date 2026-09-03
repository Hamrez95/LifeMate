\set ON_ERROR_STOP on
begin;

insert into identity.accounts(id,status,created_at_utc,updated_at_utc) values
('96500000-0000-4000-8000-000000000001','Active',now(),now()),
('96500000-0000-4000-8000-000000000002','Active',now(),now());

insert into core.persons(id,status,subject_category,created_at_utc,updated_at_utc)
values('96500000-0000-4000-8000-000000000002','Active','Adult',now(),now());
insert into core.account_person_links(account_id,person_id,link_type,status)
values('96500000-0000-4000-8000-000000000002','96500000-0000-4000-8000-000000000002','Self','Active');

insert into admin.members(account_id,status,created_by_account_id) values
('96500000-0000-4000-8000-000000000001','Active','96500000-0000-4000-8000-000000000001');
insert into admin.member_roles(account_id,role_id,granted_by_account_id)
select '96500000-0000-4000-8000-000000000001',id,'96500000-0000-4000-8000-000000000001'
from admin.roles where code='founder';

insert into consent.consent_documents(
  id,purpose,version,jurisdiction,title,document_hash,status,effective_at_utc,content_uri
) values
('96500000-0000-4000-8000-000000000101','privacy_notice','v1','GLOBAL','Privacy notice',repeat('a',64),'Active',now(),'https://legal.lifemate.app/privacy/v1'),
('96500000-0000-4000-8000-000000000102','legal_terms','v2','GLOBAL','Terms',repeat('b',64),'Draft',null,null);

insert into consent.legal_acceptances(
  account_id,actor_account_id,document_id,document_hash,source,accepted_at_utc
) values(
  '96500000-0000-4000-8000-000000000002',
  '96500000-0000-4000-8000-000000000002',
  '96500000-0000-4000-8000-000000000101',repeat('a',64),'contract.test',now()
);

insert into consent.consent_records(
  id,subject_person_id,actor_account_id,document_id,purpose,scope_key,
  data_categories,jurisdiction,source,status,granted_at_utc
) values(
  '96500000-0000-4000-8000-000000000201',
  '96500000-0000-4000-8000-000000000002',
  '96500000-0000-4000-8000-000000000002',
  '96500000-0000-4000-8000-000000000101',
  'care_sharing','relationship:synthetic',array['Treatment']::varchar[],'GLOBAL',
  'contract-test','Granted',now()
);

insert into consent.data_use_consents(
  id,subject_person_id,actor_account_id,purpose,data_categories,jurisdiction,
  policy_version,source,status,granted_at_utc
) values(
  '96500000-0000-4000-8000-000000000301',
  '96500000-0000-4000-8000-000000000002',
  '96500000-0000-4000-8000-000000000002',
  'promotional_sms',array[]::varchar[],'GLOBAL','v1','contract-test','OptedIn',now()
);

do $$
declare
  v_updated timestamptz;
  v_result jsonb;
begin
  if not admin.account_has_permission('96500000-0000-4000-8000-000000000001','privacy.consent.read') then
    raise exception 'Founder lacks privacy.consent.read';
  end if;
  if not admin.account_has_permission('96500000-0000-4000-8000-000000000001','privacy.consent.manage') then
    raise exception 'Founder lacks privacy.consent.manage';
  end if;

  if not has_table_privilege('lifemate_admin_runtime','consent.admin_document_directory_v1','SELECT')
     or not has_table_privilege('lifemate_admin_runtime','consent.admin_legal_acceptance_directory_v1','SELECT')
     or not has_table_privilege('lifemate_admin_runtime','consent.admin_user_consent_directory_v1','SELECT')
     or not has_table_privilege('lifemate_admin_runtime','consent.admin_preference_directory_v1','SELECT') then
    raise exception 'Admin runtime lacks approved privacy read views';
  end if;
  if exists(select 1 from pg_roles where rolname='authenticated') and (
    has_table_privilege('authenticated','consent.admin_document_directory_v1','SELECT')
    or has_table_privilege('authenticated','consent.admin_legal_acceptance_directory_v1','SELECT')
    or has_table_privilege('authenticated','consent.admin_user_consent_directory_v1','SELECT')
    or has_table_privilege('authenticated','consent.admin_preference_directory_v1','SELECT')
  ) then raise exception 'Browser authenticated role can read admin privacy views'; end if;

  if not exists(
    select 1 from consent.admin_user_consent_directory_v1
    where purpose='care_sharing' and status='Granted'
  ) then raise exception 'Authoritative health/care consent is missing from read-only consent ledger'; end if;
  if exists(
    select 1 from consent.admin_preference_directory_v1
    where purpose='care_sharing'
  ) then raise exception 'Clinical sharing consent leaked into generic preference directory'; end if;
  if not exists(
    select 1 from consent.admin_preference_directory_v1
    where purpose='promotional_sms' and enabled and explicit
  ) then raise exception 'Privacy preference directory lost ordinary promotional preference'; end if;

  if exists(
    select 1 from information_schema.columns
    where table_schema='consent' and table_name='admin_legal_acceptance_directory_v1'
      and column_name in ('metadata_json','email','phone','provider_subject')
  ) then raise exception 'Legal acceptance directory exposes disallowed identity/client metadata'; end if;

  select updated_at_utc into v_updated from consent.consent_documents
  where id='96500000-0000-4000-8000-000000000101';
  v_result := consent.admin_retire_document(
    '96500000-0000-4000-8000-000000000001',
    '96500000-0000-4000-8000-000000000101',
    v_updated,
    'superseded_version',
    '96500000-0000-4000-8000-000000000901'
  );
  if v_result->>'status'<>'Retired' or coalesce((v_result->>'noop')::boolean,true) then
    raise exception 'Active document retirement failed';
  end if;
  if not exists(
    select 1 from admin.audit_events
    where actor_account_id='96500000-0000-4000-8000-000000000001'
      and action='privacy.document.retired'
      and resource_id='96500000-0000-4000-8000-000000000101'
      and result='Succeeded'
  ) then raise exception 'Document retirement audit evidence missing'; end if;

  select updated_at_utc into v_updated from consent.consent_documents
  where id='96500000-0000-4000-8000-000000000102';
  begin
    perform consent.admin_retire_document(
      '96500000-0000-4000-8000-000000000001',
      '96500000-0000-4000-8000-000000000102',
      v_updated,
      'superseded_version',
      '96500000-0000-4000-8000-000000000902'
    );
    raise exception 'Draft document retirement unexpectedly succeeded';
  exception when object_not_in_prerequisite_state then null;
  end;
end
$$;

rollback;
