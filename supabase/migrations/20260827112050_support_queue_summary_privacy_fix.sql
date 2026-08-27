-- #496 privacy hardening: user free-text belongs only to the conversation body.
-- Never project it into support.tickets.queue_summary_redacted without an explicit
-- privacy-minimizing summarizer/review step.

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

    perform pg_advisory_xact_lock(hashtextextended(
      p_requester_account_id::text || ':' || p_client_message_id::text, 0
    ));

    select * into v_existing
    from support.conversation_messages
    where sender_kind='User'
      and sender_account_id=p_requester_account_id
      and client_message_id=p_client_message_id
    order by created_at_utc desc
    limit 1;
    if found then
      return jsonb_build_object(
        'ticketId', v_existing.ticket_id,
        'messageId', v_existing.id,
        'replayed', true
      );
    end if;

    insert into support.tickets(
      requester_account_id, product_code, category, status, priority,
      queue_summary_redacted, last_activity_at_utc
    ) values (
      p_requester_account_id, v_product, v_category, 'Open', 'Normal',
      null, now()
    ) returning * into v_ticket;

    insert into support.conversation_messages(
      ticket_id, sender_kind, sender_account_id, client_message_id, body
    ) values (
      v_ticket.id, 'User', p_requester_account_id, p_client_message_id, v_body
    ) returning * into v_message;

    insert into support.ticket_events(ticket_id,event_type,actor_account_id,safe_summary)
    values (v_ticket.id,'TicketCreated',p_requester_account_id,null);

    return jsonb_build_object(
      'ticketId', v_ticket.id,
      'messageId', v_message.id,
      'replayed', false
    );
end
$$;

revoke all on function support.open_support_conversation(uuid,character varying,character varying,text,uuid) from public;
do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant execute on function support.open_support_conversation(uuid,character varying,character varying,text,uuid)
      to lifemate_edge_runtime;
  end if;
end
$$;
