-- #602 Canonical care relationship classification for invite/admin reporting.
-- relationship_type is presentation/reporting metadata only. Authorization stays
-- entirely on consent, active relationship and feature/privacy grants.

alter table lifemate.care_invitations
  add column if not exists relationship_type character varying(20)
    not null default 'unknown',
  add column if not exists inviter_caregiver_display_name character varying(80);

alter table lifemate.care_relationships
  add column if not exists relationship_type character varying(20)
    not null default 'unknown';

update lifemate.care_relationships
set relationship_type = case
  when lower(coalesce(patient_relationship_type, '')) in ('partner', 'spouse')
    then 'partner'
  when lower(coalesce(patient_relationship_type, '')) in
    ('child', 'child_caring_for_parent', 'child_to_parent')
    then 'child'
  when lower(coalesce(patient_relationship_type, '')) in
    ('family', 'family_member', 'parent_caring_for_dependent',
     'parent_to_child', 'parent_to_dependent')
    then 'family'
  else relationship_type
end
where relationship_type = 'unknown';

alter table lifemate.care_invitations
  drop constraint if exists ck_care_invitations_relationship_type,
  add constraint ck_care_invitations_relationship_type check (
    relationship_type in ('partner', 'family', 'child', 'unknown')
  ),
  drop constraint if exists ck_care_invitations_inviter_caregiver_display_name,
  add constraint ck_care_invitations_inviter_caregiver_display_name check (
    inviter_caregiver_display_name is null or
    length(btrim(inviter_caregiver_display_name)) between 1 and 80
  );

alter table lifemate.care_relationships
  drop constraint if exists ck_care_relationships_relationship_type,
  add constraint ck_care_relationships_relationship_type check (
    relationship_type in ('partner', 'family', 'child', 'unknown')
  );

create index if not exists ix_care_relationships_relationship_type_status
  on lifemate.care_relationships (relationship_type, status);

comment on column lifemate.care_relationships.relationship_type is
  'Canonical admin/reporting + presentation relationship classification. Never an authorization input.';
comment on column lifemate.care_invitations.relationship_type is
  'Owner-selected canonical relationship classification carried into acceptance. Never an authorization input.';
comment on column lifemate.care_invitations.inviter_caregiver_display_name is
  'Optional owner-side nickname for the invited caregiver; copied to the viewer-specific relationship alias after acceptance.';
