-- #496: staff-visible conversation replies reuse existing support.write authority.
-- Internal notes remain support.ticket_events/InternalNoteAdded and are not exposed here.

create or replace view admin.support_conversation_messages_v1
with (security_invoker = true)
as
select
  m.id as message_id,
  m.ticket_id,
  m.sender_kind,
  m.sender_account_id,
  sender_profile.display_name as sender_display_name,
  m.body,
  m.created_at_utc
from support.conversation_messages m
left join core.account_person_links sender_link
  on sender_link.account_id=m.sender_account_id
 and sender_link.link_type='Self'
 and sender_link.status='Active'
left join core.person_profiles sender_profile
  on sender_profile.person_id=sender_link.person_id;

create or replace function admin.send_support_conversation_message(
    p_actor_account_id uuid,
    p_ticket_id uuid,
    p_body text,
    p_client_message_id uuid,
    p_correlation_id uuid,
    p_idempotency_key character varying,
    p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, support, pg_temp
as $$
declare
  v_operation constant character varying := 'support.conversation.message.send';
  v_existing admin.idempotency_keys%rowtype;
  v_ticket support.tickets%rowtype;
  v_message support.conversation_messages%rowtype;
  v_body text := trim(coalesce(p_body,''));
  v_response jsonb;
begin
  if p_actor_account_id is null or p_ticket_id is null or p_client_message_id is null
     or p_correlation_id is null then
    return jsonb_build_object('httpStatus',400,'code','support_message_invalid','message','Support message metadata is invalid.','replayed',false);
  end if;
  if length(v_body) < 1 or length(v_body) > 4000 or octet_length(v_body) > 12000 then
    return jsonb_build_object('httpStatus',400,'code','support_message_invalid','message','Support message is invalid.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation
    and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching support message is still being processed.','replayed',false);
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  if not admin.account_has_permission(p_actor_account_id,'support.write') then
    v_response := jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  else
    select * into v_ticket from support.tickets where id=p_ticket_id for update;
    if not found then
      v_response := jsonb_build_object('httpStatus',404,'code','ticket_not_found','message','Support ticket was not found.','replayed',false);
    elsif v_ticket.status='Closed' then
      v_response := jsonb_build_object('httpStatus',409,'code','support_ticket_closed','message','Closed support ticket must be reopened before replying.','replayed',false);
    end if;
  end if;

  if v_response is not null then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values(
      p_actor_account_id,'support.conversation.message.send','support_ticket',p_ticket_id::text,
      'Denied',coalesce(v_response->>'code','support_message_rejected'),p_correlation_id,
      p_idempotency_key,false,jsonb_build_object('clientMessageId',p_client_message_id)
    );
    update admin.idempotency_keys set status='Completed',
      response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
    return v_response;
  end if;

  select * into v_message from support.conversation_messages
  where ticket_id=p_ticket_id and sender_kind='Staff' and sender_account_id=p_actor_account_id
    and client_message_id=p_client_message_id;
  if not found then
    insert into support.conversation_messages(ticket_id,sender_kind,sender_account_id,client_message_id,body)
    values(p_ticket_id,'Staff',p_actor_account_id,p_client_message_id,v_body)
    returning * into v_message;
  elsif v_message.body <> v_body then
    v_response := jsonb_build_object('httpStatus',409,'code','client_message_conflict','message','The client message identifier was already used for different content.','replayed',false);
    update admin.idempotency_keys set status='Completed',response_status=409,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
    return v_response;
  end if;

  update support.tickets
  set status=case when status in ('Open','Pending') then 'WaitingOnUser' else status end,
      last_activity_at_utc=now(),updated_at_utc=now()
  where id=p_ticket_id;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,request_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'support.conversation.message.sent','support_ticket',p_ticket_id::text,
    'Succeeded','Visible support reply sent',p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('messageId',v_message.id,'clientMessageId',p_client_message_id)
  );

  v_response := jsonb_build_object(
    'httpStatus',200,'code','ok','ticketId',p_ticket_id,'messageId',v_message.id,
    'createdAtUtc',v_message.created_at_utc,'replayed',false
  );
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

revoke all on admin.support_conversation_messages_v1 from public;
revoke all on function admin.send_support_conversation_message(uuid,uuid,text,uuid,uuid,character varying,character varying) from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on admin.support_conversation_messages_v1 from %I',v_role);
      execute format(
        'revoke all on function admin.send_support_conversation_message(uuid,uuid,text,uuid,uuid,character varying,character varying) from %I',
        v_role
      );
    end if;
  end loop;
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant select on admin.support_conversation_messages_v1 to lifemate_admin_runtime;
    grant execute on function admin.send_support_conversation_message(uuid,uuid,text,uuid,uuid,character varying,character varying) to lifemate_admin_runtime;
  end if;
end
$$;

comment on view admin.support_conversation_messages_v1 is
  'Staff-visible support chat messages only. Internal notes remain in the separate support event timeline.';
