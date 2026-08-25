-- Privacy-minimized Command Center read model for existing care links.
-- A care relationship is not a natural/family relationship, so it must not be
-- backfilled into network.person_relationships with a fabricated relationship_type.

create or replace view admin.care_relationship_directory_v1
with (security_barrier = true)
as
select
    relationship.id,
    relationship.patient_person_id,
    relationship.caregiver_person_id,
    relationship.status,
    relationship.created_at_utc,
    relationship.revoked_at_utc
from lifemate.care_relationships relationship
where relationship.patient_person_id is not null
  and relationship.caregiver_person_id is not null;

comment on view admin.care_relationship_directory_v1 is
    'Privacy-minimized Admin read model for care relationships. Caregiver role is not converted into a natural person relationship and grants no health access by itself.';

revoke all on admin.care_relationship_directory_v1 from public;
grant select on admin.care_relationship_directory_v1 to lifemate_admin_runtime;
