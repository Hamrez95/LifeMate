begin;

-- Keep one canonical Active legal document per purpose/jurisdiction even when
-- two Admin publication requests race on different Draft rows.
-- This applies only to mandatory Legal Terms / Privacy Notice governance and
-- does not alter optional user-consent decisions.
create or replace function consent.serialize_active_legal_document()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, consent
as $$
begin
  if new.status <> 'Active' or new.purpose not in ('legal_terms','privacy_notice') then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('consent:active-legal:' || new.purpose || ':' || new.jurisdiction, 0)
  );

  update consent.consent_documents
  set status = 'Retired'
  where purpose = new.purpose
    and jurisdiction = new.jurisdiction
    and status = 'Active'
    and id <> new.id;

  return new;
end;
$$;

revoke all on function consent.serialize_active_legal_document() from public, anon, authenticated;

drop trigger if exists trg_consent_documents_serialize_active_legal on consent.consent_documents;
create trigger trg_consent_documents_serialize_active_legal
before insert or update of status, purpose, jurisdiction
on consent.consent_documents
for each row
execute function consent.serialize_active_legal_document();

commit;
