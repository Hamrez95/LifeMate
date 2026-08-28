begin;

-- Admin policy administration must read the policy row itself. The existing
-- admin_preference_directory_v1 is an effective per-user projection and its
-- updated_at_utc belongs to data_use_consents, so it must never be used as the
-- optimistic-concurrency token for preference_purposes updates.
create or replace view consent.admin_preference_purpose_policy_directory_v1 as
select
  p.purpose,
  p.category,
  p.channel,
  p.policy_version,
  p.default_enabled,
  p.user_mutable,
  p.status,
  p.description,
  p.created_at_utc,
  p.updated_at_utc
from consent.preference_purposes p;

revoke all on consent.admin_preference_purpose_policy_directory_v1 from public;
do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','lifemate_edge_runtime'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format(
        'revoke all on consent.admin_preference_purpose_policy_directory_v1 from %I',
        v_role
      );
    end if;
  end loop;
end
$$;

grant select on consent.admin_preference_purpose_policy_directory_v1 to lifemate_admin_runtime;

commit;
