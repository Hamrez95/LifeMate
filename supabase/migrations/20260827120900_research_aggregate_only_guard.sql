-- #497: Pseudonymous row-level export is intentionally unavailable until a
-- reviewed unlinkability/pseudonymization design is implemented. Keep the DB
-- fail-closed even if the Admin API boundary is bypassed.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ck_dataset_privacy_policies_aggregate_only'
      and conrelid = 'analytics.dataset_privacy_policies'::regclass
  ) then
    alter table analytics.dataset_privacy_policies
      add constraint ck_dataset_privacy_policies_aggregate_only
      check (row_mode = 'Aggregate');
  end if;
end $$;
