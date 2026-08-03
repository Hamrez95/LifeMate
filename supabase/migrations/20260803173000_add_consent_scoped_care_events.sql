create table if not exists lifemate.care_events (
    id uuid primary key,
    patient_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    created_by_user_id uuid not null references lifemate.app_users(id) on delete restrict,
    client_request_id uuid not null,
    event_type character varying(32) not null,
    title character varying(160) not null,
    provider_name character varying(160),
    specialty character varying(120),
    medication_name character varying(160),
    dose_text character varying(80),
    administration_route character varying(80),
    reason character varying(500),
    instructions character varying(1000),
    center_name character varying(160),
    address_line character varying(500),
    phone_number character varying(50),
    scheduled_local_date date not null,
    scheduled_local_time time without time zone not null,
    time_zone character varying(64) not null,
    status character varying(32) not null default 'Scheduled',
    completed_at_utc timestamp with time zone,
    version integer not null default 1,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint ck_care_events_event_type
        check (event_type in ('Appointment', 'Injection')),
    constraint ck_care_events_status
        check (status in ('Scheduled', 'Completed', 'Cancelled')),
    constraint ck_care_events_version check (version > 0),
    constraint uq_care_events_patient_client_request
        unique (patient_user_id, client_request_id)
);

create index if not exists ix_care_events_patient_schedule
    on lifemate.care_events(
        patient_user_id,
        scheduled_local_date,
        scheduled_local_time
    );

create index if not exists ix_care_events_creator
    on lifemate.care_events(created_by_user_id, created_at_utc desc);

-- Mobile clients never receive direct table privileges. All access is enforced
-- by the authenticated LifeMate API and active care-relationship checks.
revoke all privileges on table lifemate.care_events
    from anon, authenticated, service_role;

comment on table lifemate.care_events is
'Patient-owned appointments and injection events exposed only through the LifeMate API.';
comment on column lifemate.care_events.client_request_id is
'Patient-scoped idempotency key supplied by the client.';
