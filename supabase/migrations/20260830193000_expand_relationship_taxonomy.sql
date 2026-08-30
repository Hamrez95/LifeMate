begin;

alter table lifemate.care_invitations
  alter column relationship_type type character varying(32);

alter table lifemate.care_relationships
  alter column relationship_type type character varying(32);

alter table lifemate.care_invitations
  drop constraint if exists ck_care_invitations_relationship_type,
  add constraint ck_care_invitations_relationship_type check (
    relationship_type in (
      'partner','family','child','friend','trusted_person','doctor','nurse',
      'professional_caregiver','therapist_specialist','other','unknown'
    )
  );

alter table lifemate.care_relationships
  drop constraint if exists ck_care_relationships_relationship_type,
  add constraint ck_care_relationships_relationship_type check (
    relationship_type in (
      'partner','family','child','friend','trusted_person','doctor','nurse',
      'professional_caregiver','therapist_specialist','other','unknown'
    )
  );

comment on column lifemate.care_relationships.relationship_type is
  'Canonical relationship presentation/reporting category. Never grants authorization or consent.';
comment on column lifemate.care_invitations.relationship_type is
  'Owner-selected canonical relationship presentation category carried into acceptance. Never grants authorization or consent.';

commit;
