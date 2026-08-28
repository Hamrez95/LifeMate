begin;

-- #505 follow-up: let the authenticated consumer resume their latest own
-- non-closed support conversation without exposing queue/staff metadata.
create or replace function support.get_latest_user_support_conversation(
  p_requester_account_id uuid,
  p_product_code character varying default null,
  p_category character varying default 'general'
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
  v_category character varying(64) := lower(trim(coalesce(p_category,'general')));
begin
  if p_requester_account_id is null then
    raise exception using errcode='22023', message='support_requester_invalid';
  end if;
  if v_product is not null and v_product !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$' then
    raise exception using errcode='22023', message='support_product_invalid';
  end if;
  if v_category !~ '^[a-z0-9_-]{1,64}$' then
    raise exception using errcode='22023', message='support_category_invalid';
  end if;

  return query
  select t.id,t.status,t.product_code,t.last_activity_at_utc
  from support.tickets t
  where t.requester_account_id=p_requester_account_id
    and t.status<>'Closed'
    and t.category=v_category
    and (v_product is null or t.product_code=v_product)
  order by t.last_activity_at_utc desc,t.id desc
  limit 1;
end
$$;

-- Opening a conversation must be atomic with the resume decision. A client-side
-- GET-current followed by POST-open is inherently racy across devices, so the
-- canonical write itself serializes per account/product/category and reuses the
-- latest non-closed thread. client_message_id remains the retry identity for the
-- first message and conflicting reuse fails closed.
create or replace function support.open_support_conversation(
    p_requester_account_id uuid,
    p_product_code character varying,
    p_category character varying,
    p_body text,
    p_client_message_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = support, identity, pg_temp
as $$
declare
    v_existing support.conversation_messages%rowtype;
    v_existing_ticket support.tickets%rowtype;
    v_ticket support.tickets%rowtype;
    v_message support.conversation_messages%rowtype;
    v_body text := trim(coalesce(p_body, ''));
    v_product character varying(64) := nullif(lower(trim(coalesce(p_product_code, ''))), '');
    v_category character varying(64) := lower(trim(coalesce(p_category, 'general')));
begin
    if p_requester_account_id is null or p_client_message_id is null then
      raise exception using errcode='22023', message='support_identity_or_message_id_invalid';
    end if;
    if length(v_body) < 1 or length(v_body) > 4000 or octet_length(v_body) > 12000 then
      raise exception using errcode='22023', message='support_message_invalid';
    end if;
    if v_product is not null and v_product !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$' then
      raise exception using errcode='22023', message='support_product_invalid';
    end if;
    if v_category !~ '^[a-z0-9_-]{1,64}$' then
      raise exception using errcode='22023', message='support_category_invalid';
    end if;
    if not exists (select 1 from identity.accounts where id=p_requester_account_id) then
      raise exception using errcode='23503', message='support_requester_not_found';
    end if;

    -- One active thread decision at a time for this requester/product/category,
    -- independent of each device's client_message_id.
    perform pg_advisory_xact_lock(hashtextextended(
      p_requester_account_id::text || ':' || coalesce(v_product, '') || ':' || v_category,
      0
    ));

    select m.* into v_existing
    from support.conversation_messages m
    where m.sender_kind='User'
      and m.sender_account_id=p_requester_account_id
      and m.client_message_id=p_client_message_id
    order by m.created_at_utc desc
    limit 1;
    if found then
      select * into v_existing_ticket
      from support.tickets
      where id=v_existing.ticket_id;

      if v_existing.body <> v_body
         or v_existing_ticket.category <> v_category
         or v_existing_ticket.product_code is distinct from v_product then
        raise exception using errcode='23505', message='support_client_message_id_conflict';
      end if;

      return jsonb_build_object(
        'ticketId', v_existing.ticket_id,
        'messageId', v_existing.id,
        'replayed', true
      );
    end if;

    select * into v_ticket
    from support.tickets
    where requester_account_id=p_requester_account_id
      and status<>'Closed'
      and category=v_category
      and product_code is not distinct from v_product
    order by last_activity_at_utc desc,id desc
    limit 1
    for update;

    if found then
      return support.send_user_support_message(
        p_requester_account_id,
        v_ticket.id,
        v_body,
        p_client_message_id
      );
    end if;

    insert into support.tickets(
      requester_account_id, product_code, category, status, priority,
      queue_summary_redacted, last_activity_at_utc
    ) values (
      p_requester_account_id, v_product, v_category, 'Open', 'Normal',
      left(v_body, 280), now()
    ) returning * into v_ticket;

    insert into support.conversation_messages(
      ticket_id, sender_kind, sender_account_id, client_message_id, body
    ) values (
      v_ticket.id, 'User', p_requester_account_id, p_client_message_id, v_body
    ) returning * into v_message;

    insert into support.ticket_events(ticket_id,event_type,actor_account_id,safe_summary)
    values (v_ticket.id,'TicketCreated',p_requester_account_id,null)
    on conflict do nothing;

    return jsonb_build_object(
      'ticketId', v_ticket.id,
      'messageId', v_message.id,
      'replayed', false
    );
end
$$;

revoke all on function support.get_latest_user_support_conversation(uuid,character varying,character varying)
  from public,anon,authenticated;
revoke all on function support.open_support_conversation(uuid,character varying,character varying,text,uuid)
  from public,anon,authenticated;
grant execute on function support.get_latest_user_support_conversation(uuid,character varying,character varying)
  to lifemate_edge_runtime;
grant execute on function support.open_support_conversation(uuid,character varying,character varying,text,uuid)
  to lifemate_edge_runtime;

commit;
