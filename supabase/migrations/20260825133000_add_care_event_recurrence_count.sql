-- Additive count bound for advanced care-event recurrence.
-- Null means the series is not count-bounded. Existing rows are unchanged.

alter table lifemate.care_events
  add column if not exists recurrence_max_occurrences integer null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_max_occurrences_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_max_occurrences_check
      check (
        recurrence_max_occurrences is null
        or recurrence_max_occurrences between 1 and 10000
      );
  end if;
end $$;
