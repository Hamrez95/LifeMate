begin;

alter table lifemate.care_relationships
  drop constraint if exists ck_care_relationships_caregiver_presentation_type,
  add constraint ck_care_relationships_caregiver_presentation_type check (
    caregiver_relationship_type in (
      'partner','family','child','friend','trusted_person','doctor','nurse',
      'professional_caregiver','therapist_specialist','other','unknown'
    )
  ),
  drop constraint if exists ck_care_relationships_patient_presentation_type,
  add constraint ck_care_relationships_patient_presentation_type check (
    patient_relationship_type in (
      'partner','family','child','friend','trusted_person','doctor','nurse',
      'professional_caregiver','therapist_specialist','other','unknown'
    )
  );

comment on column lifemate.care_relationships.caregiver_relationship_type is
  'Viewer-owned canonical presentation category only; never grants access or consent.';
comment on column lifemate.care_relationships.patient_relationship_type is
  'Viewer-owned canonical presentation category only; never grants access or consent.';

commit;
