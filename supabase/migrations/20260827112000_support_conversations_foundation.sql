-- #496: canonical two-way support conversation foundation.
-- Extends support.tickets; does not create a parallel support identity/ticket model.

create table if not exists support.conversation_messages (
    id uuid primary key default gen_random_uuid(),
    ticket_id uuid not null references support.tickets(id) on delete cascade,
    sender_kind character varying(12) not null check (sender_kind in ('User','Staff')),
    sender_account_id uuid not null references identity.accounts(id) on delete restrict,
    client_message_id uuid not null,
    body text not null,
    created_at_utc timestamp with time zone not null default now(),
    check (length(trim(body)) between 1 and 4000),
    check (octet_length(body) <= 12000),
    unique (ticket_id, sender_kind, sender_account_id, client_message_id)
);

comment on table support.conversation_messages is
  'Append-only user/staff-visible support chat messages. Raw health context is never auto-enriched into this table.';

create index if not exists ix_support_conversation_messages_timeline
    on support.conversation_messages(ticket_id, created_at_utc desc, id desc);

create table if not exists support.conversation_reads (
    ticket_id uuid not null references support.tickets(id) on delete cascade,
    account_id uuid not null references identity.accounts(id) on delete cascade,
    last_read_message_id uuid references support.conversation_messages(id) on delete set null,
    read_at_utc timestamp with time zone not null default now(),
    primary key (ticket_id, account_id)
);

create table if not exists support.message_attachments (
    id uuid primary key default gen_random_uuid(),
    message_id uuid not null references support.conversation_messages(id) on delete cascade,
    uploader_account_id uuid not null references identity.accounts(id) on delete restrict,
    original_file_name character varying(180) not null,
    content_type character varying(100) not null,
    size_bytes bigint not null check (size_bytes between 1 and 10485760),
    storage_object_path character varying(500) not null unique,
    content_sha256 character(64),
    scan_status character varying(20) not null default 'Pending'
      check (scan_status in ('Pending','Scanning','Available','Rejected','ScanError','Deleted')),
    scan_reason_code character varying(80),
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    check (original_file_name !~ '[\\/]' and length(trim(original_file_name)) between 1 and 180),
    check (content_type in (
      'image/jpeg','image/png','image/webp','application/pdf','text/plain'
    )),
    check (content_sha256 is null or content_sha256 ~ '^[0-9a-f]{64}$'),
    check (scan_reason_code is null or scan_reason_code ~ '^[a-z0-9_.-]{2,80}$')
);

comment on column support.message_attachments.storage_object_path is
  'Server-owned private Storage object path. Never expose a public bucket URL.';
comment on column support.message_attachments.scan_status is
  'Attachment is downloadable only when Available; upload/scan implementation is a separate bounded provider path.';

create index if not exists ix_support_message_attachments_message
    on support.message_attachments(message_id, created_at_utc, id);
create index if not exists ix_support_message_attachments_scan_queue
    on support.message_attachments(scan_status, created_at_utc, id)
    where scan_status in ('Pending','ScanError');

alter table support.conversation_messages enable row level security;
alter table support.conversation_messages force row level security;
alter table support.conversation_reads enable row level security;
alter table support.conversation_reads force row level security;
alter table support.message_attachments enable row level security;
alter table support.message_attachments force row level security;

drop policy if exists lifemate_admin_runtime_select on support.conversation_messages;
create policy lifemate_admin_runtime_select
on support.conversation_messages for select to lifemate_admin_runtime using (true);

drop policy if exists lifemate_admin_runtime_select on support.conversation_reads;
create policy lifemate_admin_runtime_select
on support.conversation_reads for select to lifemate_admin_runtime using (true);

drop policy if exists lifemate_admin_runtime_select on support.message_attachments;
create policy lifemate_admin_runtime_select
on support.message_attachments for select to lifemate_admin_runtime using (true);

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

create or replace function support.send_user_support_message(
    p_requester_account_id uuid,
    p_ticket_id uuid,
    p_body text,
    p_client_message_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = support, pg_temp
as $$
declare
    v_ticket support.tickets%rowtype;
    v_message support.conversation_messages%rowtype;
    v_body text := trim(coalesce(p_body, ''));
begin
    if p_requester_account_id is null or p_ticket_id is null or p_client_message_id is null then
      raise exception using errcode='22023', message='support_identity_or_message_id_invalid';
    end if;
    if length(v_body) < 1 or length(v_body) > 4000 or octet_length(v_body) > 12000 then
      raise exception using errcode='22023', message='support_message_invalid';
    end if;

    select * into v_message
    from support.conversation_messages
    where ticket_id=p_ticket_id and sender_kind='User'
      and sender_account_id=p_requester_account_id
      and client_message_id=p_client_message_id;
    if found then
      return jsonb_build_object('ticketId',p_ticket_id,'messageId',v_message.id,'replayed',true);
    end if;

    select * into v_ticket from support.tickets
    where id=p_ticket_id and requester_account_id=p_requester_account_id
    for update;
    if not found then
      raise exception using errcode='42501', message='support_ticket_not_accessible';
    end if;
    if v_ticket.status='Closed' then
      raise exception using errcode='55000', message='support_ticket_closed';
    end if;

    if v_ticket.status='Resolved' then
      update support.tickets set status='Open', updated_at_utc=now() where id=p_ticket_id;
      insert into support.ticket_events(ticket_id,event_type,actor_account_id,from_value,to_value)
      values (p_ticket_id,'StatusChanged',p_requester_account_id,'Resolved','Open');
    end if;

    insert into support.conversation_messages(
      ticket_id,sender_kind,sender_account_id,client_message_id,body
    ) values (
      p_ticket_id,'User',p_requester_account_id,p_client_message_id,v_body
    ) returning * into v_message;

    update support.tickets
    set status=case when status='WaitingOnUser' then 'Open' else status end,
        last_activity_at_utc=now(), updated_at_utc=now()
    where id=p_ticket_id;

    return jsonb_build_object('ticketId',p_ticket_id,'messageId',v_message.id,'replayed',false);
end
$$;

create or replace function support.list_user_support_messages(
    p_requester_account_id uuid,
    p_ticket_id uuid,
    p_before_at timestamp with time zone default null,
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
  order by m.created_at_utc desc,m.id desc
  limit p_limit;
end
$$;

create or replace function support.mark_user_support_read(
    p_requester_account_id uuid,
    p_ticket_id uuid,
    p_message_id uuid
) returns boolean
language plpgsql
security definer
set search_path = support, pg_temp
as $$
begin
  if not exists (
    select 1 from support.tickets
    where id=p_ticket_id and requester_account_id=p_requester_account_id
  ) or not exists (
    select 1 from support.conversation_messages
    where id=p_message_id and ticket_id=p_ticket_id
  ) then
    return false;
  end if;
  insert into support.conversation_reads(ticket_id,account_id,last_read_message_id,read_at_utc)
  values (p_ticket_id,p_requester_account_id,p_message_id,now())
  on conflict (ticket_id,account_id) do update
    set last_read_message_id=excluded.last_read_message_id,
        read_at_utc=excluded.read_at_utc;
  return true;
end
$$;

revoke all on support.conversation_messages from public;
revoke all on support.conversation_reads from public;
revoke all on support.message_attachments from public;
revoke all on function support.open_support_conversation(uuid,character varying,character varying,text,uuid) from public;
revoke all on function support.send_user_support_message(uuid,uuid,text,uuid) from public;
revoke all on function support.list_user_support_messages(uuid,uuid,timestamp with time zone,integer) from public;
revoke all on function support.mark_user_support_read(uuid,uuid,uuid) from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on support.conversation_messages from %I',v_role);
      execute format('revoke all on support.conversation_reads from %I',v_role);
      execute format('revoke all on support.message_attachments from %I',v_role);
    end if;
  end loop;

  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant usage on schema support to lifemate_admin_runtime;
    grant select on support.conversation_messages,support.conversation_reads,support.message_attachments to lifemate_admin_runtime;
  end if;
  if exists(select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant usage on schema support to lifemate_edge_runtime;
    grant execute on function support.open_support_conversation(uuid,character varying,character varying,text,uuid) to lifemate_edge_runtime;
    grant execute on function support.send_user_support_message(uuid,uuid,text,uuid) to lifemate_edge_runtime;
    grant execute on function support.list_user_support_messages(uuid,uuid,timestamp with time zone,integer) to lifemate_edge_runtime;
    grant execute on function support.mark_user_support_read(uuid,uuid,uuid) to lifemate_edge_runtime;
  end if;
end
$$;
