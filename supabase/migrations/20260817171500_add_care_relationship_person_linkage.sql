-- Stage canonical Person identity on the legacy care-relationship write model.
--
-- Legacy AppUser columns remain required compatibility inputs for now. This
-- migration adds authoritative Person linkage for the next runtime migration,
-- backfills existing rows through the explicit identity bridge, and makes
-- future legacy writes fail closed when the supplied identities disagree.

alter table lifemate.care_relationships
  add column if not exists patient_person_id uuid,
  add column if not exists caregiver_person_id uuid;

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'lifemate.care_relationships'::regclass
      and conname = 'FK_care_relationships_patient_person_id'
  ) then
    alter table lifemate.care_relationships
      add constraint "FK_care_relationships_patient_person_id"
      foreign key (patient_person_id)
      references core.persons(id)
      on delete restrict;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'lifemate.care_relationships'::regclass
      and conname = 'FK_care_relationships_caregiver_person_id'
  ) then
    alter table lifemate.care_relationships
      add constraint "FK_care_relationships_caregiver_person_id"
      foreign key (caregiver_person_id)
      references core.persons(id)
      on delete restrict;
  end if;
end
$migration$;

update lifemate.care_relationships r
set patient_person_id = core.self_person_id_for_legacy_app_user(r.patient_user_id),
    caregiver_person_id = core.self_person_id_for_legacy_app_user(r.caregiver_user_id)
where r.patient_person_id is distinct from
        core.self_person_id_for_legacy_app_user(r.patient_user_id)
   or r.caregiver_person_id is distinct from
        core.self_person_id_for_legacy_app_user(r.caregiver_user_id);

do $migration$
begin
  if exists (
    select 1
    from lifemate.care_relationships
    where patient_person_id is null
       or caregiver_person_id is null
  ) then
    raise exception 'care_relationship_person_backfill_missing';
  end if;
end
$migration$;

create or replace function core.sync_care_relationship_person_ids()
returns trigger
language plpgsql
set search_path = pg_catalog, core, pg_temp
as $$
declare
  v_patient_person_id uuid;
  v_caregiver_person_id uuid;
begin
  if new.patient_user_id is null or new.caregiver_user_id is null then
    raise exception 'care_relationship_legacy_participant_missing';
  end if;

  -- A relationship identifies one fixed patient/caregiver pair. Reassigning a
  -- participant in place can leave downstream consent/access-grant state tied
  -- to the previous pair, so participant replacement must create a new domain
  -- relationship instead of mutating this row.
  if tg_op = 'UPDATE' and (
    new.patient_user_id is distinct from old.patient_user_id
    or new.caregiver_user_id is distinct from old.caregiver_user_id
  ) then
    raise exception 'care_relationship_participant_immutable';
  end if;

  v_patient_person_id := core.self_person_id_for_legacy_app_user(
    new.patient_user_id
  );
  v_caregiver_person_id := core.self_person_id_for_legacy_app_user(
    new.caregiver_user_id
  );

  if v_patient_person_id is null then
    raise exception 'care_relationship_patient_person_missing';
  end if;
  if v_caregiver_person_id is null then
    raise exception 'care_relationship_caregiver_person_missing';
  end if;

  if new.patient_person_id is null then
    new.patient_person_id := v_patient_person_id;
  elsif new.patient_person_id <> v_patient_person_id then
    raise exception 'care_relationship_patient_person_mismatch';
  end if;

  if new.caregiver_person_id is null then
    new.caregiver_person_id := v_caregiver_person_id;
  elsif new.caregiver_person_id <> v_caregiver_person_id then
    raise exception 'care_relationship_caregiver_person_mismatch';
  end if;

  return new;
end
$$;

revoke execute on function core.sync_care_relationship_person_ids() from public;

drop trigger if exists trg_sync_care_relationship_person_ids
  on lifemate.care_relationships;
create trigger trg_sync_care_relationship_person_ids
before insert or update of
  patient_user_id,
  caregiver_user_id,
  patient_person_id,
  caregiver_person_id
on lifemate.care_relationships
for each row execute function core.sync_care_relationship_person_ids();

create unique index if not exists
  "IX_care_relationships_patient_person_id_caregiver_person_id"
on lifemate.care_relationships(patient_person_id, caregiver_person_id)
where status = 'Active';

create index if not exists "IX_care_relationships_patient_person_id_status"
on lifemate.care_relationships(patient_person_id, status);

create index if not exists "IX_care_relationships_caregiver_person_id_status"
on lifemate.care_relationships(caregiver_person_id, status);
