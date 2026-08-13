-- Approved non-health read model for ADM-USR-001.
-- Restore an RLS path only for the exact non-health relations needed by the Admin API.

do $$
declare
  v_target text;
  v_schema text;
  v_table text;
begin
  foreach v_target in array array[
    'identity.accounts',
    'identity.external_identities',
    'core.account_person_links',
    'core.person_profiles',
    'ecosystem.applications',
    'ecosystem.app_enrollments'
  ] loop
    v_schema := split_part(v_target, '.', 1);
    v_table := split_part(v_target, '.', 2);
    if to_regclass(v_target) is not null then
      execute format(
        'drop policy if exists lifemate_admin_runtime_select on %I.%I',
        v_schema,
        v_table
      );
      execute format(
        'create policy lifemate_admin_runtime_select on %I.%I for select to lifemate_admin_runtime using (true)',
        v_schema,
        v_table
      );
    end if;
  end loop;
end
$$;

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

revoke all on admin.user_directory_v1 from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname = v_role) then
      execute format('revoke all on admin.user_directory_v1 from %I', v_role);
    end if;
  end loop;
end
$$;

grant select on admin.user_directory_v1 to lifemate_admin_runtime;

comment on view admin.user_directory_v1 is
  'Approved non-health LifeMate Command Center user directory read model (v1).';
