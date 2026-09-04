begin;

revoke all on table platform.product_update_policy_history from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on table platform.product_update_policy_history from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on table platform.product_update_policy_history from authenticated';
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'lifemate_admin_runtime') then
    grant select on table platform.product_update_policy_history to lifemate_admin_runtime;
  end if;
end
$$;

comment on table platform.product_update_policy_history is
  'Immutable archived Product Update Policy versions. Direct browser roles are denied; Admin runtime receives read-only access for the audited Command Center history surface.';

commit;
