begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description)
values
  ('privacy.consent.read','privacy','STANDARD',true,'Read privacy-safe legal document, acceptance and preference directories'),
  ('privacy.consent.manage','privacy','ELEVATED',true,'Retire published legal documents through audited lifecycle controls')
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

create or replace view consent.admin_document_directory_v1 as
select
  d.id as document_id,
  d.document_key,
  d.version,
  d.locale,
  d.title,
  d.summary,
  d.content_sha256,
  d.status,
  d.published_at,
  d.retired_at,
  d.created_at,
  d.updated_at,
  count(a.account_id) filter (where a.revoked_at is null) as active_acceptance_count,
  count(a.account_id) filter (where a.revoked_at is not null) as revoked_acceptance_count
from consent.documents d
left join consent.legal_acceptances a on a.document_id=d.id
group by d.id;

create or replace view consent.admin_acceptance_directory_v1 as
select
  a.account_id,
  a.document_id,
  d.document_key,
  d.version,
  d.locale,
  d.title as document_title,
  a.accepted_at,
  a.source,
  a.revoked_at,
  a.revoke_reason_code,
  case when a.revoked_at is null then 'Active' else 'Revoked' end as acceptance_status
from consent.legal_acceptances a
join consent.documents d on d.id=a.document_id;

create or replace view consent.admin_preference_directory_v1 as
select
  p.account_id,
  'Purpose'::text as preference_scope,
  p.purpose::text as preference_key,
  p.enabled,
  p.source,
  p.version,
  p.updated_at
from consent.purpose_preferences p
where p.purpose <> 'HealthSharing'::consent.preference_purpose
union all
select
  t.account_id,
  'Transport'::text,
  t.purpose::text,
  t.enabled,
  t.source,
  t.version,
  t.updated_at
from consent.transport_preferences t;

revoke all on consent.admin_document_directory_v1 from public,anon,authenticated;
revoke all on consent.admin_acceptance_directory_v1 from public,anon,authenticated;
revoke all on consent.admin_preference_directory_v1 from public,anon,authenticated;
grant select on consent.admin_document_directory_v1 to lifemate_admin_runtime;
grant select on consent.admin_acceptance_directory_v1 to lifemate_admin_runtime;
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
  v consent.documents%rowtype;
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

  select * into v from consent.documents where id=p_document_id for update;
  if not found then
    raise exception 'privacy_document_not_found' using errcode='P0002';
  end if;
  if v.updated_at is distinct from p_expected_updated_at then
    raise exception 'privacy_document_version_conflict' using errcode='40001';
  end if;
  if v.status='Draft' then
    raise exception 'privacy_draft_retirement_forbidden' using errcode='55000';
  end if;
  if v.status='Retired' then
    return jsonb_build_object('documentId',v.id,'status',v.status,'retiredAt',v.retired_at,'noop',true);
  end if;

  update consent.documents
  set status='Retired', retired_at=coalesce(retired_at,now()), updated_at=now()
  where id=v.id
  returning * into v;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,reason_code,correlation_id,safe_metadata
  ) values (
    p_actor_account_id,'privacy.document.retired','ConsentDocument',v.id::text,v_reason,p_correlation_id,
    jsonb_build_object('documentKey',v.document_key,'version',v.version,'locale',v.locale)
  );

  return jsonb_build_object('documentId',v.id,'status',v.status,'retiredAt',v.retired_at,'updatedAt',v.updated_at,'noop',false);
end
$$;

revoke all on function consent.admin_retire_document(uuid,uuid,timestamptz,varchar,uuid) from public,anon,authenticated;
grant execute on function consent.admin_retire_document(uuid,uuid,timestamptz,varchar,uuid) to lifemate_admin_runtime;

commit;
