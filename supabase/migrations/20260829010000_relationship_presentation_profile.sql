-- #110 Relationship-aware presentation metadata.
-- These fields are intentionally NOT authorization inputs. Existing grants,
-- consent scopes and active relationship checks remain the only access boundary.

alter table lifemate.care_relationships
  add column if not exists caregiver_relationship_type character varying(40)
    not null default 'unknown',
  add column if not exists caregiver_patient_display_name character varying(80),
  add column if not exists patient_relationship_type character varying(40)
    not null default 'unknown',
  add column if not exists patient_caregiver_display_name character varying(80);

alter table lifemate.care_relationships
  drop constraint if exists ck_care_relationships_caregiver_presentation_type,
  add constraint ck_care_relationships_caregiver_presentation_type check (
    caregiver_relationship_type in (
      'partner',
      'child_caring_for_parent',
      'parent_caring_for_dependent',
      'family',
      'trusted_caregiver',
      'unknown'
    )
  ),
  drop constraint if exists ck_care_relationships_patient_presentation_type,
  add constraint ck_care_relationships_patient_presentation_type check (
    patient_relationship_type in (
      'partner',
      'child_caring_for_parent',
      'parent_caring_for_dependent',
      'family',
      'trusted_caregiver',
      'unknown'
    )
  ),
  drop constraint if exists ck_care_relationships_caregiver_patient_display_name,
  add constraint ck_care_relationships_caregiver_patient_display_name check (
    caregiver_patient_display_name is null or
    length(btrim(caregiver_patient_display_name)) between 1 and 80
  ),
  drop constraint if exists ck_care_relationships_patient_caregiver_display_name,
  add constraint ck_care_relationships_patient_caregiver_display_name check (
    patient_caregiver_display_name is null or
    length(btrim(patient_caregiver_display_name)) between 1 and 80
  );

comment on column lifemate.care_relationships.caregiver_relationship_type is
  'Caregiver-owned presentation hint only; never grants access or consent.';
comment on column lifemate.care_relationships.caregiver_patient_display_name is
  'Caregiver-owned local display alias for the patient; independent of official profile name.';
comment on column lifemate.care_relationships.patient_relationship_type is
  'Patient-owned presentation hint only; never grants access or consent.';
comment on column lifemate.care_relationships.patient_caregiver_display_name is
  'Patient-owned local display alias for the caregiver; independent of official profile name.';
