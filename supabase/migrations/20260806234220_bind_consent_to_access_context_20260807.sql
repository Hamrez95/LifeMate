-- A consent decision is contextual. An unrelated active care-sharing consent
-- for the same Person must never satisfy another relationship/engagement grant.
create or replace function security.can_access_person_feature(
    p_grantee_account_id uuid,
    p_subject_person_id uuid,
    p_scope character varying,
    p_feature_code character varying,
    p_consent_purpose character varying default 'care_sharing',
    p_at_utc timestamp with time zone default now()
) returns boolean
language sql
stable
set search_path = security, core, consent, commerce, pg_temp
as $$
  select commerce.has_entitlement(
           p_grantee_account_id,p_subject_person_id,p_feature_code,p_at_utc)
     and (
       exists(
         select 1
         from core.account_person_links l
         where l.account_id=p_grantee_account_id
           and l.person_id=p_subject_person_id
           and l.link_type='Self'
           and l.status='Active'
       )
       or exists(
         select 1
         from security.access_grants g
         join security.access_grant_scopes s on s.grant_id=g.id
         join consent.consent_records c
           on c.subject_person_id=g.subject_person_id
          and c.purpose=p_consent_purpose
          and c.status='Granted'
          and c.granted_at_utc <= p_at_utc
          and (c.expires_at_utc is null or c.expires_at_utc > p_at_utc)
          and g.context_type is not null
          and g.context_id is not null
          and c.scope_key=(g.context_type || ':' || g.context_id::text)
         where g.grantee_account_id=p_grantee_account_id
           and g.subject_person_id=p_subject_person_id
           and g.status='Active'
           and g.starts_at_utc <= p_at_utc
           and (g.expires_at_utc is null or g.expires_at_utc > p_at_utc)
           and s.scope=p_scope
       )
     )
$$;

revoke execute on function security.can_access_person_feature(uuid,uuid,character varying,character varying,character varying,timestamp with time zone)
from public, anon, authenticated, service_role;
