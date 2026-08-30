begin;

-- Test/admin gift finalization stays inside canonical Commerce/Growth.
-- No real gateway integration is introduced here.
create or replace function growth.test_finalize_subscription_gift(
  p_gift_intent_id uuid,
  p_transaction_id uuid,
  p_claim_token_hash varchar,
  p_claim_ttl_hours integer default 168
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,growth,commerce,pg_temp
as $$
begin
  return growth.mark_subscription_gift_paid(
    p_gift_intent_id,
    p_transaction_id,
    p_claim_token_hash,
    p_claim_ttl_hours
  );
end $$;

revoke all on function growth.test_finalize_subscription_gift(uuid,uuid,varchar,integer) from public,anon,authenticated;
do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function growth.test_finalize_subscription_gift(uuid,uuid,varchar,integer) to lifemate_admin_runtime;
  end if;
end $$;

comment on function growth.test_finalize_subscription_gift(uuid,uuid,varchar,integer) is
'Test/admin-only gift payment simulation boundary. Delegates to the canonical settled-payment validator; never use as a public checkout endpoint.';

commit;
