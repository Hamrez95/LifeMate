\set ON_ERROR_STOP on
begin;

insert into identity.accounts(id,status,created_at_utc,updated_at_utc) values
('96500000-0000-4000-8000-000000000001','Active',now(),now()),
('96500000-0000-4000-8000-000000000002','Active',now(),now());

insert into admin.members(account_id,status,created_by_account_id) values
('96500000-0000-4000-8000-000000000001','Active','96500000-0000-4000-8000-000000000001');
insert into admin.member_roles(account_id,role_id,granted_by_account_id)
select '96500000-0000-4000-8000-000000000001',id,'96500000-0000-4000-8000-000000000001'
from admin.roles where code='founder';

insert into consent.documents(
  id,document_key,version,locale,title,summary,content_sha256,status,published_at
) values
('96500000-0000-4000-8000-000000000101','privacy_notice',1,'fa-IR','Privacy notice','Synthetic test notice',repeat('a',64),'Published',now()),
('96500000-0000-4000-8000-000000000102','terms_of_use',2,'fa-IR','Terms','Synthetic draft terms',repeat('b',64),'Draft',null);

insert into consent.legal_acceptances(account_id,document_id,accepted_at,source)
values('96500000-0000-4000-8000-000000000002','96500000-0000-4000-8000-000000000101',now(),'contract-test');

insert into consent.purpose_preferences(account_id,purpose,enabled,source,version)
values
('96500000-0000-4000-8000-000000000002','Analytics',true,'contract-test',1),
('96500000-0000-4000-8000-000000000002','HealthSharing',false,'contract-test',1);

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
     or not has_table_privilege('lifemate_admin_runtime','consent.admin_acceptance_directory_v1','SELECT')
     or not has_table_privilege('lifemate_admin_runtime','consent.admin_preference_directory_v1','SELECT') then
    raise exception 'Admin runtime lacks approved privacy read views';
  end if;
  if exists(select 1 from pg_roles where rolname='authenticated') and (
    has_table_privilege('authenticated','consent.admin_document_directory_v1','SELECT')
    or has_table_privilege('authenticated','consent.admin_acceptance_directory_v1','SELECT')
    or has_table_privilege('authenticated','consent.admin_preference_directory_v1','SELECT')
  ) then raise exception 'Browser authenticated role can read admin privacy views'; end if;

  if exists(
    select 1 from consent.admin_preference_directory_v1
    where preference_key='HealthSharing'
  ) then raise exception 'Generic admin preference view exposed authoritative HealthSharing consent'; end if;
  if not exists(
    select 1 from consent.admin_preference_directory_v1
    where preference_key='Analytics' and enabled
  ) then raise exception 'Privacy preference directory lost ordinary Analytics preference'; end if;

  if exists(
    select 1 from information_schema.columns
    where table_schema='consent' and table_name='admin_acceptance_directory_v1'
      and column_name in ('user_agent_hash','metadata_json','email','phone')
  ) then raise exception 'Acceptance directory exposes disallowed identity/client metadata'; end if;

  select updated_at into v_updated from consent.documents
  where id='96500000-0000-4000-8000-000000000101';
  v_result := consent.admin_retire_document(
    '96500000-0000-4000-8000-000000000001',
    '96500000-0000-4000-8000-000000000101',
    v_updated,
    'superseded_version',
    '96500000-0000-4000-8000-000000000901'
  );
  if v_result->>'status'<>'Retired' or coalesce((v_result->>'noop')::boolean,true) then
    raise exception 'Published document retirement failed';
  end if;
  if not exists(
    select 1 from admin.audit_events
    where actor_account_id='96500000-0000-4000-8000-000000000001'
      and action='privacy.document.retired'
      and resource_id='96500000-0000-4000-8000-000000000101'
      and result='Succeeded'
  ) then raise exception 'Document retirement audit evidence missing'; end if;

  select updated_at into v_updated from consent.documents
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
