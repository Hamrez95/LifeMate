alter table lifemate.medication_schedule_optimization_proposals
  add column if not exists undone_at_utc timestamptz;

alter table lifemate.medication_schedule_optimization_plan_changes
  add column if not exists applied_treatment_plan_version integer;

alter table lifemate.medication_schedule_optimization_plan_changes
  drop constraint if exists medication_schedule_optimization_plan_changes_applied_treatment_plan_version_check;
alter table lifemate.medication_schedule_optimization_plan_changes
  add constraint medication_schedule_optimization_plan_changes_applied_treatment_plan_version_check
  check (
    applied_treatment_plan_version is null
    or applied_treatment_plan_version > expected_treatment_plan_version
  );

alter table lifemate.medication_schedule_optimization_proposals
  drop constraint if exists medication_schedule_optimization_proposals_status_check;
alter table lifemate.medication_schedule_optimization_proposals
  add constraint medication_schedule_optimization_proposals_status_check
  check (status in ('Previewed','Applied','Undone','Expired','Cancelled','Stale'));

comment on column lifemate.medication_schedule_optimization_plan_changes.applied_treatment_plan_version is
  'Version produced by the accepted strict optimization. Undo fails closed unless the plan is still exactly at this version.';
comment on column lifemate.medication_schedule_optimization_proposals.undone_at_utc is
  'Timestamp of an explicit owner-triggered strict optimization undo. Historical adherence remains immutable.';
