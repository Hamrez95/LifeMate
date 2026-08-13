-- Approved non-health read model for ADM-USR-001.
create or replace view admin.user_directory_v1
with (security_invoker = true)
as
select
    a.id as account_id,
    self_link.person_id,
    profile.display_name,
    a.status as account_status,
    a.created_at_utc,
    enrollments.application_codes,
    enrollments.last_active_at_utc
from identity.accounts a
left join core.account_person_links self_link
  on self_link.account_id = a.id
 and self_link.link_type = 'Self'
 and self_link.status = 'Active'
left join core.person_profiles profile
  on profile.person_id = self_link.person_id
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

grant select on admin.user_directory_v1 to lifemate_admin_runtime;

comment on view admin.user_directory_v1 is
  'Approved non-health LifeMate Command Center user directory read model (v1).';
