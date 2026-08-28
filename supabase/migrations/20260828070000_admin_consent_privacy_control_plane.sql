begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description)
values
  ('privacy.consent.read','privacy','STANDARD',true,'Read privacy-safe legal document, acceptance, consent and preference directories'),
  ('privacy.consent.manage','privacy','ELEVATED',true,'Retire active legal documents through audited lifecycle controls')
on conflict (code) do update
set domain=excluded.domain,
    risk_level=excluded.risk_level,
    role_assignable=excluded.role_assignable,
    description=excluded.description,
    updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join (values('privacy.consent.read'),('privacy.consent.manage')) p(code)
where r.code in ('founder','super_admin')
on conflict do nothing;

alter table consent.consent_documents
  add column if not exists updated_at_utc timestamptz not null default now(),
  add column if not exists retired_at_utc timestamptz;

create or replace view consent.admin_document_directory_v1 as
select
  d.id as document_id,
  d.purpose,
  d.version,
  d.jurisdiction,
  d.title,
  d.document_hash,
  d.content_uri,
  d.status,
  d.effective_at_utc,
  d.created_at_utc,
  d.updated_at_utc,
  d.retired_at_utc,
  count(a.account_id) as acceptance_count
from consent.consent_documents d
left join consent.legal_acceptances a on a.document_id=d.id
group by d.id;

create or replace view consent.admin_legal_acceptance_directory_v1 as
select
  a.account_id,
  a.document_id,
  d.purpose,
  d.version,
  d.jurisdiction,
  d.title as document_title,
  a.document_hash,
  a.source,
  a.accepted_at_utc
from consent.legal_acceptances a
join consent.consent_documents d on d.id=a.document_id;

create or replace view consent.admin_user_consent_directory_v1 as
select
  r.id as consent_record_id,
  r.subject_person_id,
  r.actor_account_id,
  r.document_id,
  d.title as document_title,
  d.version as document_version,
  r.purpose,
  r.scope_key,
  r.data_categories,
  r.jurisdiction,
  r.source,
  r.status,
  r.granted_at_utc,
  r.revoked_at_utc,
  r.expires_at_utc,
  r.created_at_utc,
  r.updated_at_utc
from consent.consent_records r
join consent.consent_documents d on d.id=r.document_id;

create or replace view consent.admin_preference_directory_v1 as
select
  l.account_id,
  l.person_id as subject_person_id,
  p.purpose,
  p.category,
  p.channel,
  p.policy_version,
  p.default_enabled,
  p.user_mutable,
  coalesce(c.status='OptedIn',p.default_enabled) as enabled,
  (c.id is not null) as explicit,
  coalesce(c.status,'Default') as consent_status,
  c.jurisdiction,
  c.source,
  c.updated_at_utc
from consent.preference_purposes p
cross join core.account_person_links l
left join consent.data_use_consents c
  on c.subject_person_id=l.person_id
 and c.purpose=p.purpose
 and c.policy_version=p.policy_version
where p.status='Active'
  and l.link_type='Self'
  and l.status='Active';

revoke all on consent.admin_document_directory_v1 from public;
revoke all on consent.admin_legal_acceptance_directory_v1 from public;
revoke all on consent.admin_user_consent_directory_v1 from public;
revoke all on consent.admin_preference_directory_v1 from public;
do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on consent.admin_document_directory_v1 from %I',v_role);
      execute format('revoke all on consent.admin_legal_acceptance_directory_v1 from %I',v_role);
      execute format('revoke all on consent.admin_user_consent_directory_v1 from %I',v_role);
      execute format('revoke all on consent.admin_preference_directory_v1 from %I',v_role);
    end if;
  end loop;
end
$$;
grant select on consent.admin_document_directory_v1 to lifemate_admin_runtime;
grant select on consent.admin_legal_acceptance_directory_v1 to lifemate_admin_runtime;
grant select on consent.admin_user_consent_directory_v1 to lifemate_admin_runtime;
grant select on consent.admin_preference_directory_v1 to lifemate_admin_runtime;

create or replace function consent.admin_retire_document(
  p_actor_account_id uuid,
  p_document_id uuid,
  p_expected_updated_at timestamptz,
  p_reason_code varchar,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,consent,admin
as $$
declare
  v consent.consent_documents%rowtype;
  v_reason text := lower(btrim(coalesce(p_reason_code,'')));
begin
  if p_actor_account_id is null or p_document_id is null or p_expected_updated_at is null or p_correlation_id is null then
    raise exception 'privacy_retire_input_invalid' using errcode='22023';
  end if;
  if v_reason !~ '^[a-z0-9_.-]{3,80}$' then
    raise exception 'privacy_retire_reason_invalid' using errcode='22023';
  end if;
  if not admin.account_has_permission(p_actor_account_id,'privacy.consent.manage',now()) then
    raise exception 'privacy_retire_forbidden' using errcode='42501';
  end if;

  select * into v from consent.consent_documents where id=p_document_id for update;
  if not found then
    raise exception 'privacy_document_not_found' using errcode='P0002';
  end if;
  if v.updated_at_utc is distinct from p_expected_updated_at then
    raise exception 'privacy_document_version_conflict' using errcode='40001';
  end if;
  if v.status='Draft' then
    raise exception 'privacy_draft_retirement_forbidden' using errcode='55000';
  end if;
  if v.status='Retired' then
    return jsonb_build_object(
      'documentId',v.id,'status',v.status,'retiredAtUtc',v.retired_at_utc,
      'updatedAtUtc',v.updated_at_utc,'noop',true
    );
  end if;

  update consent.consent_documents
  set status='Retired', retired_at_utc=coalesce(retired_at_utc,now()), updated_at_utc=now()
  where id=v.id
  returning * into v;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,request_id,elevated_access,metadata_json
  ) values (
    p_actor_account_id,'privacy.document.retired','consent_document',v.id::text,
    'Succeeded',v_reason,p_correlation_id,null,false,
    jsonb_build_object(
      'purpose',v.purpose,'version',v.version,'jurisdiction',v.jurisdiction
    )
  );

  return jsonb_build_object(
    'documentId',v.id,'status',v.status,'retiredAtUtc',v.retired_at_utc,
    'updatedAtUtc',v.updated_at_utc,'noop',false
  );
end
$$;

revoke all on function consent.admin_retire_document(uuid,uuid,timestamptz,varchar,uuid) from public;
do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format(
        'revoke all on function consent.admin_retire_document(uuid,uuid,timestamptz,varchar,uuid) from %I',
        v_role
      );
    end if;
  end loop;
end
$$;
grant execute on function consent.admin_retire_document(uuid,uuid,timestamptz,varchar,uuid) to lifemate_admin_runtime;

commit;
