begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('privacy.governance.read','privacy','SENSITIVE',true,'Read legal document versions, acceptance coverage and optional privacy purpose catalog'),
('privacy.governance.write','privacy','HIGH_RISK',true,'Publish or retire legal documents and update optional privacy purpose wording/status')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,'privacy.governance.read'
from admin.roles r
where r.code in ('founder','super_admin','security','support','marketing')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'privacy.governance.write'
from admin.roles r
where r.code in ('founder','super_admin','security')
on conflict do nothing;

-- Admin governance is deliberately narrower than end-user consent authority.
-- Admin may manage document/catalog metadata and read aggregate acceptance evidence,
-- but may never create legal_acceptance rows or mutate user consent decisions.
do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant select,insert,update on consent.consent_documents to lifemate_admin_runtime;
    grant select on consent.legal_acceptances to lifemate_admin_runtime;
    grant select,update on consent.preference_purposes to lifemate_admin_runtime;
    grant select on consent.data_use_consents,consent.data_use_consent_events to lifemate_admin_runtime;
  end if;
end $$;

-- FORCE RLS is retained. Policies are role-scoped and never include browser roles.
drop policy if exists consent_documents_admin_governance_select on consent.consent_documents;
create policy consent_documents_admin_governance_select on consent.consent_documents
  for select to lifemate_admin_runtime using (true);
drop policy if exists consent_documents_admin_governance_insert on consent.consent_documents;
create policy consent_documents_admin_governance_insert on consent.consent_documents
  for insert to lifemate_admin_runtime with check (purpose in ('legal_terms','privacy_notice'));
drop policy if exists consent_documents_admin_governance_update on consent.consent_documents;
create policy consent_documents_admin_governance_update on consent.consent_documents
  for update to lifemate_admin_runtime
  using (purpose in ('legal_terms','privacy_notice'))
  with check (purpose in ('legal_terms','privacy_notice'));

drop policy if exists legal_acceptances_admin_governance_select on consent.legal_acceptances;
create policy legal_acceptances_admin_governance_select on consent.legal_acceptances
  for select to lifemate_admin_runtime using (true);

drop policy if exists preference_purposes_admin_governance_select on consent.preference_purposes;
create policy preference_purposes_admin_governance_select on consent.preference_purposes
  for select to lifemate_admin_runtime using (true);
drop policy if exists preference_purposes_admin_governance_update on consent.preference_purposes;
create policy preference_purposes_admin_governance_update on consent.preference_purposes
  for update to lifemate_admin_runtime using (true) with check (true);

-- Explicitly preserve the non-impersonation boundary.
revoke insert,update,delete on consent.legal_acceptances from lifemate_admin_runtime;
revoke insert,update,delete on consent.data_use_consents from lifemate_admin_runtime;
revoke insert,update,delete on consent.data_use_consent_events from lifemate_admin_runtime;

commit;
