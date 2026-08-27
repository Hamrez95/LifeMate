begin;

-- #505 follow-up: let the authenticated consumer resume their latest own
-- non-closed support conversation without exposing queue/staff metadata.
create or replace function support.get_latest_user_support_conversation(
  p_requester_account_id uuid,
  p_product_code character varying default null
) returns table(
  ticket_id uuid,
  status character varying,
  product_code character varying,
  last_activity_at_utc timestamp with time zone
)
language plpgsql
security definer
set search_path = support, pg_temp
as $$
declare
  v_product character varying(64) := nullif(lower(trim(coalesce(p_product_code,''))), '');
begin
  if p_requester_account_id is null then
    raise exception using errcode='22023', message='support_requester_invalid';
  end if;
  if v_product is not null and v_product !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$' then
    raise exception using errcode='22023', message='support_product_invalid';
  end if;

  return query
  select t.id,t.status,t.product_code,t.last_activity_at_utc
  from support.tickets t
  where t.requester_account_id=p_requester_account_id
    and t.status<>'Closed'
    and (v_product is null or t.product_code=v_product)
  order by t.last_activity_at_utc desc,t.id desc
  limit 1;
end
$$;

revoke all on function support.get_latest_user_support_conversation(uuid,character varying)
  from public,anon,authenticated;
grant execute on function support.get_latest_user_support_conversation(uuid,character varying)
  to lifemate_edge_runtime;

commit;
