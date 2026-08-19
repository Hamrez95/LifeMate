-- #379 / #289 / #217
-- Women Calendar support actions are already authorized/read/exported through
-- canonical Person identity. Retire the patient's AppUser id from new writes
-- without deleting historical compatibility data or caregiver actor provenance.

-- Fail closed if an older deployment somehow left an unmapped support row.
do $$
begin
  if exists (
    select 1
    from lifemate.women_calendar_support_actions
    where patient_person_id is null
  ) then
    raise exception 'women_calendar_support_patient_person_backfill_incomplete';
  end if;
end
$$;

alter table lifemate.women_calendar_support_actions
  alter column patient_person_id set not null;

alter table lifemate.women_calendar_support_actions
  alter column patient_user_id drop not null;

comment on column lifemate.women_calendar_support_actions.patient_person_id is
  'Canonical women-health data subject. Required for all current support actions.';
comment on column lifemate.women_calendar_support_actions.patient_user_id is
  'Legacy patient AppUser compatibility identifier. Historical rows may retain it; new Person-authoritative runtime writes leave it NULL.';
comment on column lifemate.women_calendar_support_actions.caregiver_user_id is
  'Caregiver actor/audit provenance retained deliberately; not patient ownership.';
