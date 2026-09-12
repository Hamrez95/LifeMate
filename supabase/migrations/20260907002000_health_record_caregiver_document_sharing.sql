-- Caregiver Health Record document reads are an independent, read-only consent.
-- A care relationship alone never grants document access. The grant is bound to
-- one active relationship, one caregiver Account and the patient's Person.

insert into consent.consent_documents(
  purpose, version, jurisdiction, title, status, effective_at_utc
) values (
  'health_record_sharing',
  'health-record-documents-sharing-v1',
  '*',
  'Health Record document sharing consent',
  'Active',
  now()
)
on conflict(purpose, version, jurisdiction) do update
set status = 'Active', updated_at_utc = now();

create or replace function security.can_access_health_document_scope(
  p_grantee_account_id uuid,
  p_subject_person_id uuid,
  p_scope character varying,
  p_at_utc timestamp with time zone default now()
) returns boolean language sql stable
set search_path = pg_catalog,security,core,consent,lifemate
as $$
  select case
    when not exists (
      select 1 from security.scope_catalog
      where scope = p_scope and domain = 'health_record'
    ) then false
    when exists (
      select 1 from core.account_person_links l
      where l.account_id = p_grantee_account_id
        and l.person_id = p_subject_person_id
        and l.link_type = 'Self' and l.status = 'Active'
    ) then true
    else exists (
      select 1
      from security.access_grants g
      join security.access_grant_scopes gs
        on gs.grant_id = g.id and gs.scope = p_scope
      join lifemate.care_relationships r
        on r.id = g.context_id
       and g.context_type = 'health_record_relationship'
       and r.patient_person_id = g.subject_person_id
       and r.status = 'Active'
      join core.account_person_links caregiver_link
        on caregiver_link.account_id = g.grantee_account_id
       and caregiver_link.person_id = r.caregiver_person_id
       and caregiver_link.link_type = 'Self'
       and caregiver_link.status = 'Active'
      join consent.consent_records c
        on c.subject_person_id = g.subject_person_id
       and c.purpose = 'health_record_sharing'
       and c.scope_key = (
         'health_record_relationship:' || r.id::text ||
         ':grantee:' || g.grantee_account_id::text
       )
       and c.status = 'Granted'
       and c.granted_at_utc <= p_at_utc
       and (c.expires_at_utc is null or c.expires_at_utc > p_at_utc)
      where g.subject_person_id = p_subject_person_id
        and g.grantee_account_id = p_grantee_account_id
        and g.status = 'Active'
        and g.starts_at_utc <= p_at_utc
        and (g.expires_at_utc is null or g.expires_at_utc > p_at_utc)
    )
  end
$$;

revoke execute on function security.can_access_health_document_scope(
  uuid,uuid,character varying,timestamp with time zone
) from public;

do $migration$
begin
  if to_regrole('lifemate_edge_runtime') is not null then
    grant execute on function security.can_access_health_document_scope(
      uuid,uuid,character varying,timestamp with time zone
    ) to lifemate_edge_runtime;
  end if;
end $migration$;

comment on function security.can_access_health_document_scope(
  uuid,uuid,character varying,timestamp with time zone
) is
  'Fail-closed Health Record authorization: Self owner or exact relationship-bound grant + read scope + explicit current grantee-specific consent. Relationship, entitlement and legacy care-management permission alone never authorize document access.';
