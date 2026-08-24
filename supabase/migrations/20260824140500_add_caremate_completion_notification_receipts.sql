create table if not exists lifemate.caregiver_completion_notification_receipts (
    id uuid primary key default gen_random_uuid(),
    caregiver_person_id uuid not null references core.persons(id) on delete cascade,
    relationship_id uuid not null references lifemate.care_relationships(id) on delete cascade,
    source_adherence_event_id uuid not null references lifemate.dose_adherence_events(id) on delete cascade,
    claimed_at_utc timestamp with time zone not null default now(),
    unique(caregiver_person_id, source_adherence_event_id)
);

create index if not exists ix_caregiver_completion_receipts_relationship
    on lifemate.caregiver_completion_notification_receipts(relationship_id, claimed_at_utc desc);

create index if not exists ix_caregiver_completion_receipts_source
    on lifemate.caregiver_completion_notification_receipts(source_adherence_event_id);
