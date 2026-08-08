begin;

alter table lifemate.treatment_plans
  add column if not exists patient_reminder_minutes_before integer not null default 30,
  add column if not exists caregiver_reminder_minutes_before integer not null default 60;

alter table lifemate.care_events
  add column if not exists patient_reminder_minutes_before integer not null default 30,
  add column if not exists caregiver_reminder_minutes_before integer not null default 60;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_treatment_plans_patient_reminder_lead'
      and conrelid = 'lifemate.treatment_plans'::regclass
  ) then
    alter table lifemate.treatment_plans
      add constraint ck_treatment_plans_patient_reminder_lead
      check (patient_reminder_minutes_before between 0 and 10080);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_treatment_plans_caregiver_reminder_lead'
      and conrelid = 'lifemate.treatment_plans'::regclass
  ) then
    alter table lifemate.treatment_plans
      add constraint ck_treatment_plans_caregiver_reminder_lead
      check (caregiver_reminder_minutes_before between 0 and 10080);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_care_events_patient_reminder_lead'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint ck_care_events_patient_reminder_lead
      check (patient_reminder_minutes_before between 0 and 10080);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_care_events_caregiver_reminder_lead'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint ck_care_events_caregiver_reminder_lead
      check (caregiver_reminder_minutes_before between 0 and 10080);
  end if;
end $$;

commit;
