-- Canonical consumer username belongs to the login Account, not Person and not workforce staff.
-- Existing users are intentionally left NULL because live Auth/profile data contains no trustworthy username source.

alter table identity.accounts
  add column if not exists username character varying(64);

alter table identity.accounts
  drop constraint if exists ck_identity_accounts_username_format;

alter table identity.accounts
  add constraint ck_identity_accounts_username_format
  check (
    username is null
    or (
      username = btrim(username)
      and char_length(username) between 3 and 64
      and username !~ '[[:cntrl:]]'
    )
  );

create unique index if not exists uq_identity_accounts_username_ci
  on identity.accounts (lower(username))
  where username is not null;

comment on column identity.accounts.username is
  'Optional canonical consumer username. Distinct from admin.staff_profiles.username; never inferred from email, phone or display name.';

create or replace view admin.user_directory_v1
with (security_barrier = true)
as
select
    a.id as account_id,
    self_link.person_id,
    profile.display_name,
    a.status as account_status,
    a.created_at_utc,
    enrollments.application_codes,
    enrollments.last_active_at_utc,
    a.username
from identity.accounts a
left join core.account_person_links self_link
  on self_link.account_id = a.id
 and self_link.link_type = 'Self'
 and self_link.status = 'Active'
left join core.person_profiles profile on profile.person_id = self_link.person_id
left join lateral (
  select
    coalesce(
      array_agg(distinct application.code order by application.code)
        filter (where enrollment.status = 'Active'),
      array[]::character varying[]
    ) as application_codes,
    max(enrollment.last_active_at_utc) as last_active_at_utc
  from ecosystem.app_enrollments enrollment
  join ecosystem.applications application
    on application.id = enrollment.application_id
   and application.status = 'Active'
  where enrollment.account_id = a.id
) enrollments on true
where a.status <> 'Deleted';

revoke all on admin.user_directory_v1 from public;
grant select on admin.user_directory_v1 to lifemate_admin_runtime;
