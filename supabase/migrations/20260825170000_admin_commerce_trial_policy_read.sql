begin;

-- Safe read boundary for Command Center trial-policy editing. The underlying
-- table remains FORCE RLS / no-direct-access; Admin runtime can only obtain the
-- bounded policy fields required for optimistic concurrency.
create or replace function admin.get_commerce_trial_policy(p_plan_id uuid)
returns table(
  plan_id uuid,
  duration_days smallint,
  eligibility_rule character varying,
  status character varying,
  version integer,
  created_at_utc timestamptz,
  updated_at_utc timestamptz
)
language sql
stable
security definer
set search_path = admin, commerce, pg_temp
as $$
  select
    policy.plan_id,
    policy.duration_days,
    policy.eligibility_rule,
    policy.status,
    policy.version,
    policy.created_at_utc,
    policy.updated_at_utc
  from commerce.trial_policies policy
  where policy.plan_id = p_plan_id
  limit 1
$$;

revoke all on function admin.get_commerce_trial_policy(uuid) from public;
grant execute on function admin.get_commerce_trial_policy(uuid) to lifemate_admin_runtime;

commit;
