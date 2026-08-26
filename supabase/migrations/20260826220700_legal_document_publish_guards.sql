begin;

alter table identity.accounts
  alter column registration_policy_version type varchar(512);

alter table consent.consent_documents
  drop constraint if exists ck_consent_documents_active_legal_content;
alter table consent.consent_documents
  add constraint ck_consent_documents_active_legal_content
  check (
    purpose not in ('legal_terms','privacy_notice')
    or status <> 'Active'
    or (
      content_uri is not null
      and document_hash is not null
      and document_hash ~ '^[A-Za-z0-9:_-]{16,128}$'
    )
  );

comment on column consent.consent_documents.content_uri is
  'HTTPS location of the exact user-readable document. Active mandatory legal documents require this value and a bounded content hash.';

commit;
