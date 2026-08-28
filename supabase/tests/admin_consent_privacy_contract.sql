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
  id,purpose,version,jurisdiction,title,document_hash,status,effective_at_utc
) values
('96500000-0000-4000-8000-000000000101','privacy_notice','v1','GLOBAL','Privacy notice',repeat('a',64),'Active',now()),
('96500000-0000-4000-8000-000000000102','legal_terms','v2','GLOBAL','Terms',repeat('b',64),'Draft',null);

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

-- Complete #565: aggregate coverage + minimized User 360 + purpose catalog +
-- idempotent Draft->Publish lifecycle, while proving Admin cannot alter a user choice.
do $$
declare
  v_result jsonb;
  v_replay jsonb;
  v_conflict jsonb;
  v_document_id uuid;
  v_updated timestamptz;
  v_purpose_updated timestamptz;
begin
  v_result:=consent.admin_acceptance_coverage(
    '96500000-0000-4000-8000-000000000001','GLOBAL'
  );
  if jsonb_typeof(v_result->'items')<>'array' or (v_result->>'eligibleAccountCount')::integer<>2 then
    raise exception 'Aggregate acceptance coverage contract invalid';
  end if;
  if v_result::text like '%96500000-0000-4000-8000-000000000002%' then
    raise exception 'Aggregate coverage leaked account identity';
  end if;

  v_result:=consent.admin_preference_purpose_catalog('96500000-0000-4000-8000-000000000001');
  if not exists(
    select 1 from jsonb_array_elements(v_result->'items') x
    where x->>'purpose'='promotional_sms' and (x->>'defaultEnabled')::boolean=false
  ) then raise exception 'Preference purpose catalog missing safe default'; end if;

  v_result:=consent.admin_account_privacy_summary(
    '96500000-0000-4000-8000-000000000001',
    '96500000-0000-4000-8000-000000000002','GLOBAL'
  );
  if v_result->>'accountId'<>'96500000-0000-4000-8000-000000000002'
     or jsonb_typeof(v_result->'preferences')<>'array' then
    raise exception 'User privacy summary invalid';
  end if;
  if v_result::text like '%care_sharing%' or v_result::text like '%Treatment%' then
    raise exception 'User privacy summary leaked clinical consent payload';
  end if;

  v_result:=consent.admin_create_document_idempotent(
    '96500000-0000-4000-8000-000000000001','legal_terms','v3','GLOBAL','Terms v3',
    repeat('c',64),'https://example.test/legal/v3',now()+interval '1 day','new_version',
    '96500000-0000-4000-8000-000000000903','privacy-create-0001',repeat('d',64)
  );
  if (v_result->>'httpStatus')::integer<>201 or v_result->>'status'<>'Draft' then
    raise exception 'Idempotent document create failed';
  end if;
  v_document_id:=(v_result->>'documentId')::uuid;

  v_replay:=consent.admin_create_document_idempotent(
    '96500000-0000-4000-8000-000000000001','legal_terms','v3','GLOBAL','Terms v3',
    repeat('c',64),'https://example.test/legal/v3',now()+interval '1 day','new_version',
    '96500000-0000-4000-8000-000000000903','privacy-create-0001',repeat('d',64)
  );
  if coalesce((v_replay->>'replayed')::boolean,false)<>true or v_replay->>'documentId'<>v_document_id::text then
    raise exception 'Document create idempotency replay failed';
  end if;
  v_conflict:=consent.admin_create_document_idempotent(
    '96500000-0000-4000-8000-000000000001','legal_terms','v4','GLOBAL','Different request',
    repeat('e',64),'https://example.test/legal/v4',now()+interval '2 days','new_version',
    '96500000-0000-4000-8000-000000000904','privacy-create-0001',repeat('f',64)
  );
  if (v_conflict->>'httpStatus')::integer<>409 or v_conflict->>'code'<>'idempotency_conflict' then
    raise exception 'Document idempotency conflict not enforced';
  end if;

  select updated_at_utc into v_updated from consent.consent_documents where id=v_document_id;
  v_result:=consent.admin_publish_document_idempotent(
    '96500000-0000-4000-8000-000000000001',v_document_id,v_updated,now()+interval '1 day',
    'publish_version','96500000-0000-4000-8000-000000000905','privacy-publish-0001',repeat('1',64)
  );
  if v_result->>'status'<>'Active' then raise exception 'Draft publish failed'; end if;

  select updated_at_utc into v_purpose_updated from consent.preference_purposes where purpose='promotional_sms';
  v_result:=consent.admin_update_preference_purpose_idempotent(
    '96500000-0000-4000-8000-000000000001','promotional_sms',v_purpose_updated,
    'Updated optional SMS wording.','v2','Active','wording_update',
    '96500000-0000-4000-8000-000000000906','privacy-purpose-0001',repeat('2',64)
  );
  if v_result->>'policyVersion'<>'v2' then raise exception 'Purpose policy update failed'; end if;
  if (select default_enabled from consent.preference_purposes where purpose='promotional_sms') then
    raise exception 'Admin purpose update changed default opt-in';
  end if;
  if not exists(
    select 1 from consent.data_use_consents
    where id='96500000-0000-4000-8000-000000000301' and policy_version='v1' and status='OptedIn'
  ) then raise exception 'Admin purpose update mutated user consent evidence'; end if;

  if not exists(
    select 1 from admin.audit_events
    where actor_account_id='96500000-0000-4000-8000-000000000001'
      and action in ('privacy.document.created','privacy.document.published','privacy.preference_purpose.updated')
    group by actor_account_id having count(*)=3
  ) then raise exception 'Privacy completion audit evidence missing'; end if;

  if has_function_privilege(
    'lifemate_admin_runtime',
    'consent.set_account_privacy_preference(uuid,character varying,boolean,character varying,character varying)',
    'EXECUTE'
  ) then raise exception 'Admin runtime can mutate user privacy preference'; end if;

  if exists(select 1 from pg_roles where rolname='authenticated') and (
    has_function_privilege('authenticated','consent.admin_acceptance_coverage(uuid,character varying)','EXECUTE')
    or has_function_privilege('authenticated','consent.admin_account_privacy_summary(uuid,uuid,character varying)','EXECUTE')
    or has_function_privilege('authenticated','consent.admin_create_document_idempotent(uuid,character varying,character varying,character varying,character varying,character varying,text,timestamp with time zone,character varying,uuid,character varying,character varying)','EXECUTE')
  ) then raise exception 'Browser role can execute Admin privacy completion contracts'; end if;
end
$$;

rollback;
