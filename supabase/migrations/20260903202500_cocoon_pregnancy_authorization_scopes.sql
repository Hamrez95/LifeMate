-- CocoonMate pregnancy authorization foundation.
-- Relationship, consent, access grant and commerce remain separate concepts.

insert into security.scope_catalog(scope,domain,sensitivity,description) values
('pregnancy.summary.read','pregnancy','HIGHLY_SENSITIVE','Read a bounded pregnancy summary and derived gestational age for an explicitly shared active episode'),
('pregnancy.calendar.read','pregnancy','HIGHLY_SENSITIVE','Read pregnancy plan/calendar events explicitly shared for an active episode'),
('pregnancy.observations.read','pregnancy','HIGHLY_SENSITIVE','Read pregnancy-context health observations explicitly shared for an active episode'),
('pregnancy.appointments.read','pregnancy','HIGHLY_SENSITIVE','Read pregnancy-context appointments explicitly shared for an active episode'),
('pregnancy.medications.read','pregnancy','HIGHLY_SENSITIVE','Read pregnancy medication context explicitly shared for an active episode'),
('pregnancy.documents.read','pregnancy','HIGHLY_SENSITIVE','Read future pregnancy document resources explicitly shared for an active episode'),
('pregnancy.support.write','pregnancy','HIGHLY_SENSITIVE','Create explicitly permitted collaborative pregnancy support/check-in input'),
('pregnancy.owner.manage','pregnancy','HIGHLY_SENSITIVE','Owner-only pregnancy lifecycle, dating, sharing and administrative actions')
on conflict(scope) do update set
  domain=excluded.domain,
  sensitivity=excluded.sensitivity,
  description=excluded.description;

create or replace function security.can_access_pregnancy_scope(
  p_grantee_account_id uuid,
  p_subject_person_id uuid,
  p_episode_id uuid,
  p_scope character varying,
  p_at_utc timestamp with time zone default now()
) returns boolean
language sql
stable
set search_path=pg_catalog,security,core,consent,pregnancy
as $$
  select case
    -- Unknown/non-pregnancy capabilities always fail closed.
    when not exists(
      select 1
      from security.scope_catalog sc
      where sc.scope=p_scope and sc.domain='pregnancy'
    ) then false

    -- When an episode is supplied it must canonically belong to the subject.
    when p_episode_id is not null and not exists(
      select 1
      from pregnancy.episodes e
      where e.id=p_episode_id and e.mother_person_id=p_subject_person_id
    ) then false

    -- The subject's active Self account is the owner. Owner access is not
    -- derived from a relationship, consent grant or commercial entitlement.
    when exists(
      select 1
      from core.account_person_links l
      where l.account_id=p_grantee_account_id
        and l.person_id=p_subject_person_id
        and l.link_type='Self'
        and l.status='Active'
    ) then true

    -- Cross-person access is episode-scoped. Owner management can never be
    -- delegated through access_grant_scopes, even if a bad row is inserted.
    when p_episode_id is null or p_scope='pregnancy.owner.manage' then false

    else exists(
      select 1
      from pregnancy.episodes e
      join security.access_grants g
        on g.subject_person_id=e.mother_person_id
       and g.grantee_account_id=p_grantee_account_id
       and g.context_type='pregnancy_episode'
       and g.context_id=e.id
       and g.status='Active'
       and g.starts_at_utc <= p_at_utc
       and (g.expires_at_utc is null or g.expires_at_utc > p_at_utc)
      join security.access_grant_scopes gs
        on gs.grant_id=g.id and gs.scope=p_scope
      join consent.consent_records c
        on c.subject_person_id=e.mother_person_id
       and c.purpose='pregnancy_sharing'
       and c.scope_key=('pregnancy_episode:' || e.id::text)
       and c.status='Granted'
       and c.granted_at_utc <= p_at_utc
       and (c.expires_at_utc is null or c.expires_at_utc > p_at_utc)
      where e.id=p_episode_id
        and e.mother_person_id=p_subject_person_id
        -- Shared access ends with the active pregnancy episode. Historical
        -- pregnancy sharing requires a separately reviewed future contract.
        and e.status='active'
    )
  end
$$;

revoke execute on function security.can_access_pregnancy_scope(
  uuid,uuid,uuid,character varying,timestamp with time zone
) from public;

do $migration$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if to_regrole(role_name) is not null then
      execute format(
        'revoke execute on function security.can_access_pregnancy_scope(uuid,uuid,uuid,character varying,timestamp with time zone) from %I',
        role_name
      );
    end if;
  end loop;

  if to_regrole('lifemate_edge_runtime') is not null then
    grant execute on function security.can_access_pregnancy_scope(
      uuid,uuid,uuid,character varying,timestamp with time zone
    ) to lifemate_edge_runtime;
  end if;
end
$migration$;

comment on function security.can_access_pregnancy_scope(
  uuid,uuid,uuid,character varying,timestamp with time zone
) is
  'Fail-closed pregnancy authorization: Self owner OR active episode-scoped grant + exact scope + explicit pregnancy_sharing consent. Relationship and commerce state do not authorize health data.';
