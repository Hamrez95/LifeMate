-- Canonical portable PostgreSQL baseline for fresh LifeMate databases.
-- Existing deployed databases already contain these objects from the frozen
-- historical EF Core migrations; this file is intentionally idempotent.

create extension if not exists pgcrypto;
create schema if not exists lifemate;

create table if not exists lifemate.app_users (
    id uuid primary key,
    auth_subject character varying(256) not null,
    status character varying(32) not null,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null
);
create unique index if not exists "IX_app_users_auth_subject"
    on lifemate.app_users(auth_subject);

create table if not exists lifemate.user_profiles (
    id uuid primary key,
    user_id uuid not null references lifemate.app_users(id) on delete restrict,
    display_name character varying(120) not null,
    phone_number character varying(32),
    email character varying(320),
    locale character varying(16) not null default 'fa',
    time_zone character varying(64) not null default 'Asia/Tehran',
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null
);
create unique index if not exists "IX_user_profiles_user_id"
    on lifemate.user_profiles(user_id);
create index if not exists "IX_user_profiles_phone_number"
    on lifemate.user_profiles(phone_number);
create index if not exists "IX_user_profiles_email"
    on lifemate.user_profiles(email);

create table if not exists lifemate.privacy_consents (
    id uuid primary key,
    user_id uuid not null references lifemate.app_users(id) on delete restrict,
    document_type character varying(32) not null,
    document_version character varying(64) not null,
    granted_at_utc timestamp with time zone not null,
    revoked_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null
);
create index if not exists "IX_privacy_consents_user_id_document_type_document_version"
    on lifemate.privacy_consents(user_id, document_type, document_version);

create table if not exists lifemate.audit_logs (
    id uuid primary key,
    actor_user_id uuid references lifemate.app_users(id) on delete set null,
    action character varying(128) not null,
    resource_type character varying(128) not null,
    resource_id uuid,
    metadata_json jsonb,
    created_at_utc timestamp with time zone not null
);
create index if not exists "IX_audit_logs_actor_user_id"
    on lifemate.audit_logs(actor_user_id);
create index if not exists "IX_audit_logs_created_at_utc"
    on lifemate.audit_logs(created_at_utc);
create index if not exists "IX_audit_logs_resource_type_resource_id"
    on lifemate.audit_logs(resource_type, resource_id);

create table if not exists lifemate.care_invitations (
    id uuid primary key,
    inviter_user_id uuid not null references lifemate.app_users(id) on delete restrict,
    contact_type character varying(16) not null,
    contact_hash character varying(128) not null,
    contact_hint character varying(160) not null,
    token_hash character varying(128) not null,
    patient_consent_version character varying(64) not null,
    status character varying(32) not null,
    expires_at_utc timestamp with time zone not null,
    responded_by_user_id uuid references lifemate.app_users(id) on delete restrict,
    responded_at_utc timestamp with time zone,
    revoked_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null
);
create unique index if not exists "IX_care_invitations_token_hash"
    on lifemate.care_invitations(token_hash);
create unique index if not exists "IX_care_invitations_inviter_user_id_contact_hash"
    on lifemate.care_invitations(inviter_user_id, contact_hash)
    where status = 'Pending';
create index if not exists "IX_care_invitations_expires_at_utc"
    on lifemate.care_invitations(expires_at_utc);
create index if not exists "IX_care_invitations_responded_by_user_id"
    on lifemate.care_invitations(responded_by_user_id);

create table if not exists lifemate.care_relationships (
    id uuid primary key,
    patient_user_id uuid not null references lifemate.app_users(id) on delete restrict,
    caregiver_user_id uuid not null references lifemate.app_users(id) on delete restrict,
    status character varying(32) not null,
    patient_consent_version character varying(64) not null,
    patient_consented_at_utc timestamp with time zone not null,
    caregiver_consent_version character varying(64) not null,
    caregiver_consented_at_utc timestamp with time zone not null,
    revoked_by_user_id uuid references lifemate.app_users(id) on delete restrict,
    revoked_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null
);
create unique index if not exists "IX_care_relationships_patient_user_id_caregiver_user_id"
    on lifemate.care_relationships(patient_user_id, caregiver_user_id)
    where status = 'Active';
create index if not exists "IX_care_relationships_caregiver_user_id"
    on lifemate.care_relationships(caregiver_user_id);
create index if not exists "IX_care_relationships_revoked_by_user_id"
    on lifemate.care_relationships(revoked_by_user_id);

create table if not exists lifemate.medications (
    id uuid primary key,
    owner_user_id uuid not null references lifemate.app_users(id) on delete restrict,
    name character varying(120) not null,
    strength_text character varying(80),
    form character varying(50),
    notes character varying(500),
    version integer not null,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint "CK_medications_version_positive" check (version > 0)
);
create index if not exists "IX_medications_owner_user_id_name"
    on lifemate.medications(owner_user_id, name);

create table if not exists lifemate.treatment_plans (
    id uuid primary key,
    patient_user_id uuid not null references lifemate.app_users(id) on delete restrict,
    medication_id uuid not null references lifemate.medications(id) on delete restrict,
    dose_text character varying(80) not null,
    instructions character varying(500),
    start_date date not null,
    end_date date,
    time_zone character varying(64) not null,
    status character varying(32) not null,
    version integer not null,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint "CK_treatment_plans_version_positive" check (version > 0),
    constraint "CK_treatment_plans_date_range" check (end_date is null or end_date >= start_date)
);
create index if not exists "IX_treatment_plans_medication_id"
    on lifemate.treatment_plans(medication_id);
create index if not exists "IX_treatment_plans_patient_user_id_status"
    on lifemate.treatment_plans(patient_user_id, status);

create table if not exists lifemate.treatment_schedules (
    id uuid primary key,
    treatment_plan_id uuid not null references lifemate.treatment_plans(id) on delete cascade,
    day_of_week character varying(16) not null,
    local_time time without time zone not null,
    created_at_utc timestamp with time zone not null
);
create unique index if not exists "IX_treatment_schedules_treatment_plan_id_day_of_week_local_time"
    on lifemate.treatment_schedules(treatment_plan_id, day_of_week, local_time);

create table if not exists lifemate.dose_occurrences (
    id uuid primary key,
    patient_user_id uuid not null references lifemate.app_users(id) on delete restrict,
    treatment_plan_id uuid not null references lifemate.treatment_plans(id) on delete restrict,
    treatment_schedule_id uuid not null,
    scheduled_at_utc timestamp with time zone not null,
    scheduled_local_date date not null,
    scheduled_local_time time without time zone not null,
    time_zone character varying(64) not null,
    status character varying(32) not null,
    responded_at_utc timestamp with time zone,
    version integer not null,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint "CK_dose_occurrences_version_positive" check (version > 0)
);
create unique index if not exists "IX_dose_occurrences_treatment_schedule_id_scheduled_at_utc"
    on lifemate.dose_occurrences(treatment_schedule_id, scheduled_at_utc);
create index if not exists "IX_dose_occurrences_patient_user_id_scheduled_local_date"
    on lifemate.dose_occurrences(patient_user_id, scheduled_local_date);
create index if not exists "IX_dose_occurrences_patient_user_id_status_scheduled_at_utc"
    on lifemate.dose_occurrences(patient_user_id, status, scheduled_at_utc);
create index if not exists "IX_dose_occurrences_treatment_plan_id"
    on lifemate.dose_occurrences(treatment_plan_id);

create table if not exists lifemate.dose_adherence_events (
    id uuid primary key,
    occurrence_id uuid not null references lifemate.dose_occurrences(id) on delete cascade,
    actor_user_id uuid not null references lifemate.app_users(id) on delete restrict,
    client_request_id uuid not null,
    event_type character varying(32) not null,
    previous_status character varying(32) not null,
    resulting_status character varying(32) not null,
    occurred_at_utc timestamp with time zone not null,
    recorded_at_utc timestamp with time zone not null
);
create unique index if not exists "IX_dose_adherence_events_actor_user_id_client_request_id"
    on lifemate.dose_adherence_events(actor_user_id, client_request_id);
create index if not exists "IX_dose_adherence_events_occurrence_id_recorded_at_utc"
    on lifemate.dose_adherence_events(occurrence_id, recorded_at_utc);

do $migration$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if exists (select 1 from pg_roles where rolname = role_name) then
      execute format('revoke usage on schema lifemate from %I', role_name);
      execute format('revoke all privileges on all tables in schema lifemate from %I', role_name);
    end if;
  end loop;
end
$migration$;
