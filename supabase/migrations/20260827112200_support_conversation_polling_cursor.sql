-- #496: authenticated polling fallback for new support messages.
-- Realtime transport may be layered later, but browser clients never subscribe
-- directly to the sensitive support tables.

create or replace function support.list_user_support_messages_v2(
    p_requester_account_id uuid,
    p_ticket_id uuid,
    p_before_at timestamp with time zone default null,
    p_after_at timestamp with time zone default null,
    p_limit integer default 50
) returns table(
    message_id uuid,
    sender_kind character varying,
    body text,
    created_at_utc timestamp with time zone
)
language plpgsql
security definer
set search_path = support, pg_temp
as $$
begin
  if p_limit < 1 or p_limit > 100 then
    raise exception using errcode='22023', message='support_page_size_invalid';
  end if;
  if p_before_at is not null and p_after_at is not null then
    raise exception using errcode='22023', message='support_cursor_conflict';
  end if;
  if not exists (
    select 1 from support.tickets
    where id=p_ticket_id and requester_account_id=p_requester_account_id
  ) then
    raise exception using errcode='42501', message='support_ticket_not_accessible';
  end if;

  return query
  select m.id,m.sender_kind,m.body,m.created_at_utc
  from support.conversation_messages m
  where m.ticket_id=p_ticket_id
    and (p_before_at is null or m.created_at_utc < p_before_at)
    and (p_after_at is null or m.created_at_utc > p_after_at)
  order by m.created_at_utc desc,m.id desc
  limit p_limit;
end
$$;

revoke all on function support.list_user_support_messages_v2(
  uuid,uuid,timestamp with time zone,timestamp with time zone,integer
) from public;
do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant execute on function support.list_user_support_messages_v2(
      uuid,uuid,timestamp with time zone,timestamp with time zone,integer
    ) to lifemate_edge_runtime;
  end if;
end
$$;
