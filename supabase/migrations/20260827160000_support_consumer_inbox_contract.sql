-- #505: user-facing support inbox/read models on top of canonical support.tickets.
-- Only the owning requester can resolve these functions through the Edge runtime.

create or replace function support.list_user_support_conversations(
    p_requester_account_id uuid,
    p_limit integer default 20
) returns table(
    ticket_id uuid,
    ticket_number bigint,
    product_code character varying,
    category character varying,
    status character varying,
    priority character varying,
    last_activity_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone,
    unread_staff_count bigint,
    latest_message_body text,
    latest_message_sender_kind character varying,
    latest_message_at_utc timestamp with time zone
)
language plpgsql
stable
security definer
set search_path = support, pg_temp
as $$
begin
  if p_requester_account_id is null then
    raise exception using errcode='22023', message='support_requester_invalid';
  end if;
  if p_limit < 1 or p_limit > 50 then
    raise exception using errcode='22023', message='support_page_size_invalid';
  end if;

  return query
  select
    t.id,
    t.ticket_number,
    t.product_code,
    t.category,
    t.status,
    t.priority,
    t.last_activity_at_utc,
    t.created_at_utc,
    (
      select count(*)
      from support.conversation_messages sm
      where sm.ticket_id=t.id
        and sm.sender_kind='Staff'
        and sm.created_at_utc > coalesce(
          (
            select rm.created_at_utc
            from support.conversation_reads cr
            join support.conversation_messages rm
              on rm.id=cr.last_read_message_id and rm.ticket_id=cr.ticket_id
            where cr.ticket_id=t.id and cr.account_id=p_requester_account_id
          ),
          '-infinity'::timestamptz
        )
    )::bigint,
    latest.body,
    latest.sender_kind,
    latest.created_at_utc
  from support.tickets t
  left join lateral (
    select m.body,m.sender_kind,m.created_at_utc
    from support.conversation_messages m
    where m.ticket_id=t.id
    order by m.created_at_utc desc,m.id desc
    limit 1
  ) latest on true
  where t.requester_account_id=p_requester_account_id
  order by t.last_activity_at_utc desc,t.id desc
  limit p_limit;
end
$$;

create or replace function support.list_user_support_messages_v3(
    p_requester_account_id uuid,
    p_ticket_id uuid,
    p_before_at timestamp with time zone default null,
    p_after_at timestamp with time zone default null,
    p_limit integer default 50
) returns table(
    message_id uuid,
    sender_kind character varying,
    body text,
    created_at_utc timestamp with time zone,
    attachments jsonb
)
language plpgsql
stable
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
  select
    m.id,
    m.sender_kind,
    m.body,
    m.created_at_utc,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'attachmentId',a.id,
        'fileName',a.original_file_name,
        'contentType',a.content_type,
        'sizeBytes',a.size_bytes,
        'scanStatus',a.scan_status
      ) order by a.created_at_utc,a.id)
      from support.message_attachments a
      where a.message_id=m.id and a.scan_status <> 'Deleted'
    ),'[]'::jsonb)
  from support.conversation_messages m
  where m.ticket_id=p_ticket_id
    and (p_before_at is null or m.created_at_utc < p_before_at)
    and (p_after_at is null or m.created_at_utc > p_after_at)
  order by
    case when p_after_at is not null then m.created_at_utc end asc,
    case when p_after_at is null then m.created_at_utc end desc,
    m.id
  limit p_limit;
end
$$;

revoke all on function support.list_user_support_conversations(uuid,integer) from public;
revoke all on function support.list_user_support_messages_v3(uuid,uuid,timestamp with time zone,timestamp with time zone,integer) from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on function support.list_user_support_conversations(uuid,integer) from %I',v_role);
      execute format('revoke all on function support.list_user_support_messages_v3(uuid,uuid,timestamp with time zone,timestamp with time zone,integer) from %I',v_role);
    end if;
  end loop;
  if exists(select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant usage on schema support to lifemate_edge_runtime;
    grant execute on function support.list_user_support_conversations(uuid,integer) to lifemate_edge_runtime;
    grant execute on function support.list_user_support_messages_v3(uuid,uuid,timestamp with time zone,timestamp with time zone,integer) to lifemate_edge_runtime;
  end if;
end
$$;

comment on function support.list_user_support_conversations(uuid,integer) is
  'Requester-owned support inbox summary. Never returns internal notes or staff-only metadata.';
comment on function support.list_user_support_messages_v3(uuid,uuid,timestamp with time zone,timestamp with time zone,integer) is
  'Requester-owned visible conversation messages with only safe attachment metadata; signed URLs require a separate authorized request.';
