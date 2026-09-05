-- Health Record document authorization foundation.
-- Storage objects remain private and are addressed only by the reviewed API.
-- PostgreSQL stores document metadata, lifecycle and cross-domain links; it
-- never stores the healthcare file bytes.

insert into security.scope_catalog(scope, domain, sensitivity, description) values
  ('health_record.documents.read', 'health_record', 'HIGHLY_SENSITIVE',
   'Read an explicitly shared Health Record document and its bounded metadata'),
  ('health_record.documents.write', 'health_record', 'HIGHLY_SENSITIVE',
   'Create or link an explicitly shared Health Record document'),
  ('health_record.documents.delete', 'health_record', 'HIGHLY_SENSITIVE',
   'Delete an explicitly shared Health Record document')
on conflict(scope) do update set
  domain = excluded.domain,
  sensitivity = excluded.sensitivity,
  description = excluded.description;

create table if not exists lifemate.health_documents (
  id uuid primary key default gen_random_uuid(),
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  -- Generated opaque Storage object key. User name, document label and PHI
  -- must never be embedded in this value.
  storage_object_key character varying(200) not null unique,
  content_type character varying(100) not null check (content_type in (
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'
  )),
  byte_size integer not null check (byte_size > 0 and byte_size <= 15728640),
  sha256_hex character(64) not null check (sha256_hex ~ '^[0-9a-f]{64}$'),
  category character varying(40) not null check (category in (
    'prescription', 'lab_result', 'imaging', 'visit', 'injection',
    'discharge', 'vaccination', 'other'
  )),
  source_product character varying(40) not null default 'wellmate',
  captured_on date,
  -- Filename is intentionally not persisted. UI can derive a safe label from
  -- category/content type; future encrypted display labels need a dedicated
  -- reviewed encryption contract rather than silently storing PHI here.
  status character varying(24) not null default 'PendingUpload' check (status in (
    'PendingUpload', 'Available', 'Rejected', 'DeleteRequested', 'Deleted'
  )),
  created_by_account_id uuid references identity.accounts(id) on delete restrict,
  deleted_at_utc timestamp with time zone,
  created_at_utc timestamp with time zone not null default now(),
  updated_at_utc timestamp with time zone not null default now(),
  unique(owner_person_id, sha256_hex)
);

create index if not exists ix_health_documents_owner_created
  on lifemate.health_documents(owner_person_id, created_at_utc desc)
  where status = 'Available';

create table if not exists lifemate.health_document_links (
  document_id uuid not null references lifemate.health_documents(id) on delete cascade,
  context_type character varying(40) not null check (context_type in (
    'treatment_plan', 'care_event'
  )),
  context_id uuid not null,
  created_at_utc timestamp with time zone not null default now(),
  primary key(document_id, context_type, context_id)
);

create index if not exists ix_health_document_links_context
  on lifemate.health_document_links(context_type, context_id);

create table if not exists lifemate.health_document_audit_events (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references lifemate.health_documents(id) on delete restrict,
  actor_account_id uuid references identity.accounts(id) on delete restrict,
  action character varying(32) not null check (action in (
    'Created', 'Uploaded', 'Linked', 'Previewed', 'Downloaded', 'DeleteRequested', 'Deleted', 'Rejected'
  )),
  occurred_at_utc timestamp with time zone not null default now(),
  metadata_json jsonb
);
create index if not exists ix_health_document_audit_document_time
  on lifemate.health_document_audit_events(document_id, occurred_at_utc desc);

-- A contextual link can only point to a record owned by the document owner.
-- There is deliberately no polymorphic FK because contexts live in different
-- tables; this trigger preserves the ownership invariant server-side.
create or replace function lifemate.assert_health_document_link_owner()
returns trigger language plpgsql set search_path = pg_catalog,lifemate as $$
declare document_owner uuid;
begin
  select owner_person_id into document_owner
  from lifemate.health_documents where id = new.document_id;
  if document_owner is null then
    raise exception 'health_document_not_found' using errcode = '23503';
  end if;
  if new.context_type = 'treatment_plan' and not exists (
    select 1 from lifemate.treatment_plans
    where id = new.context_id and patient_person_id = document_owner
  ) then
    raise exception 'health_document_link_owner_mismatch' using errcode = '23514';
  end if;
  if new.context_type = 'care_event' and not exists (
    select 1 from lifemate.care_events
    where id = new.context_id and patient_person_id = document_owner
  ) then
    raise exception 'health_document_link_owner_mismatch' using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists trg_health_document_link_owner on lifemate.health_document_links;
create trigger trg_health_document_link_owner
before insert or update on lifemate.health_document_links
for each row execute function lifemate.assert_health_document_link_owner();

create or replace function security.can_access_health_document_scope(
  p_grantee_account_id uuid,
  p_subject_person_id uuid,
  p_scope character varying,
  p_at_utc timestamp with time zone default now()
) returns boolean language sql stable
set search_path = pg_catalog,security,core,consent
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
      join security.access_grant_scopes gs on gs.grant_id = g.id and gs.scope = p_scope
      join consent.consent_records c
        on c.subject_person_id = g.subject_person_id
       and c.purpose = 'health_record_sharing'
       and c.scope_key = ('health_record_person:' || g.subject_person_id::text)
       and c.status = 'Granted'
       and c.granted_at_utc <= p_at_utc
       and (c.expires_at_utc is null or c.expires_at_utc > p_at_utc)
      where g.subject_person_id = p_subject_person_id
        and g.grantee_account_id = p_grantee_account_id
        and g.context_type = 'health_record_person'
        and g.context_id = p_subject_person_id
        and g.status = 'Active'
        and g.starts_at_utc <= p_at_utc
        and (g.expires_at_utc is null or g.expires_at_utc > p_at_utc)
    )
  end
$$;

revoke execute on function security.can_access_health_document_scope(uuid,uuid,character varying,timestamp with time zone) from public;
do $migration$
begin
  if to_regrole('lifemate_edge_runtime') is not null then
    grant execute on function security.can_access_health_document_scope(uuid,uuid,character varying,timestamp with time zone)
      to lifemate_edge_runtime;
  end if;
end $migration$;

comment on function security.can_access_health_document_scope(uuid,uuid,character varying,timestamp with time zone) is
  'Fail-closed Health Record authorization: Self owner or exact Health Record grant + scope + explicit current consent. Relationship and entitlement never authorize document access.';
