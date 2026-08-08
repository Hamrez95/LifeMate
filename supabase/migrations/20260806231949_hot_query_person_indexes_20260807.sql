-- Query-pattern indexes for Person-owned timelines and treatment dashboards.

create index if not exists ix_medications_owner_person_updated
  on lifemate.medications(owner_person_id,updated_at_utc desc,id);

create index if not exists ix_treatment_plans_person_updated
  on lifemate.treatment_plans(patient_person_id,updated_at_utc desc,id);

create index if not exists ix_dose_occurrences_person_local_date
  on lifemate.dose_occurrences(patient_person_id,scheduled_local_date,scheduled_at_utc,id);

create index if not exists ix_dose_occurrences_person_status_time
  on lifemate.dose_occurrences(patient_person_id,status,scheduled_at_utc,id);

create index if not exists ix_consent_latest_subject_purpose
  on consent.consent_records(subject_person_id,purpose,created_at_utc desc,id);

-- Current CareMate remains on legacy relationships during compatibility;
-- the existing caregiver index is retained. New scope resolution uses this.
create index if not exists ix_access_grants_grantee_status_subject
  on security.access_grants(grantee_account_id,status,subject_person_id,expires_at_utc,id);
