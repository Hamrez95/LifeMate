begin;

-- #616 Canonical, transactional Free quota guard. Commercial truth stays in Commerce.
create or replace function commerce.assert_free_quota(
  p_app_user_id uuid,
  p_policy_key text,
  p_current_count integer
) returns void
language plpgsql security definer
set search_path=pg_catalog,commerce,identity,pg_temp
as $$
declare
  v_account uuid;
  v_limit integer;
  v_premium boolean;
begin
  v_account := identity.account_id_for_legacy_app_user(p_app_user_id);
  if v_account is null then
    raise exception using errcode='P0001', message='identity_account_mapping_missing';
  end if;

  -- Serialize quota-sensitive writes for this account so concurrent creates cannot bypass the boundary.
  perform pg_advisory_xact_lock(hashtextextended(v_account::text || ':' || p_policy_key, 0));

  select exists(
    select 1 from commerce.subscriptions s
    join commerce.products p on p.id=s.product_id
    where s.owner_account_id=v_account
      and p.code='wellmate-caremate'
      and s.status='Active'
      and s.starts_at_utc<=now()
      and (s.current_period_end_utc is null or s.current_period_end_utc>now())
  ) into v_premium;
  if v_premium then return; end if;

  select (cp.value_json #>> '{}')::integer into v_limit
  from commerce.catalog_policies cp
  join commerce.products p on p.id=cp.product_id
  where p.code='wellmate-caremate'
    and cp.policy_key=p_policy_key and cp.status='Active';

  if v_limit is null then
    raise exception using errcode='P0001', message='commerce_quota_policy_missing';
  end if;
  if p_current_count >= v_limit then
    raise exception using errcode='P0001', message='premium_required_quota_reached';
  end if;
end $$;

revoke all on function commerce.assert_free_quota(uuid,text,integer) from public;
grant execute on function commerce.assert_free_quota(uuid,text,integer) to lifemate_edge_runtime;

commit;
