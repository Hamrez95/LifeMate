-- Add an internal Account target for privacy-safe phone care requests.
-- Pending requests grant no healthcare access; relationship/consent creation remains
-- a separate owner-approved action in the API.

alter table lifemate.care_invitations
  add column if not exists target_account_id uuid;

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'lifemate.care_invitations'::regclass
      and conname = 'FK_care_invitations_target_account_id'
  ) then
    alter table lifemate.care_invitations
      add constraint "FK_care_invitations_target_account_id"
      foreign key (target_account_id)
      references identity.accounts(id)
      on delete set null;
  end if;
end
$migration$;

comment on column lifemate.care_invitations.target_account_id is
  'Internal matched Account for in-app phone care requests. Nullable for privacy-preserving unmatched requests; never grants healthcare access by itself.';

create index if not exists "IX_care_invitations_target_account_pending"
  on lifemate.care_invitations(target_account_id, expires_at_utc, created_at_utc desc)
  where contact_type = 'CareRequestPhone' and status = 'Pending';
