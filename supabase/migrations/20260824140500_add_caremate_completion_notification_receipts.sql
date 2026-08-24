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

alter table lifemate.caregiver_completion_notification_receipts enable row level security;
alter table lifemate.caregiver_completion_notification_receipts force row level security;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'lifemate_edge_runtime') then
    grant select, insert, update, delete
      on lifemate.caregiver_completion_notification_receipts
      to lifemate_edge_runtime;
    drop policy if exists lifemate_edge_runtime_access
      on lifemate.caregiver_completion_notification_receipts;
    create policy lifemate_edge_runtime_access
      on lifemate.caregiver_completion_notification_receipts
      for all to lifemate_edge_runtime
      using (true) with check (true);
  end if;
end
$$;
