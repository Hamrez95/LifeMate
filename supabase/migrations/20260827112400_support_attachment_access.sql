-- #496: attachment registration, scan finalization and download projection.
-- Storage remains private; only Available attachments may receive signed URLs.

create or replace function support.register_user_support_attachment(
    p_requester_account_id uuid,
    p_ticket_id uuid,
    p_message_id uuid,
    p_original_file_name character varying,
    p_content_type character varying,
    p_size_bytes bigint,
    p_storage_object_path character varying,
    p_content_sha256 character
) returns jsonb
language plpgsql
security definer
set search_path = support, pg_temp
as $$
declare
  v_attachment support.message_attachments%rowtype;
begin
  if p_requester_account_id is null or p_ticket_id is null or p_message_id is null then
    raise exception using errcode='22023', message='support_attachment_identity_invalid';
  end if;
  if not exists (
    select 1 from support.tickets t
    where t.id=p_ticket_id and t.requester_account_id=p_requester_account_id
  ) then
    raise exception using errcode='42501', message='support_ticket_not_accessible';
  end if;
  if not exists (
    select 1 from support.conversation_messages m
    where m.id=p_message_id and m.ticket_id=p_ticket_id
  ) then
    raise exception using errcode='23503', message='support_message_not_found';
  end if;
  if p_storage_object_path not like p_requester_account_id::text || '/' || p_ticket_id::text || '/' || p_message_id::text || '/%' then
    raise exception using errcode='22023', message='support_attachment_path_invalid';
  end if;

  insert into support.message_attachments(
    message_id,uploader_account_id,original_file_name,content_type,size_bytes,
    storage_object_path,content_sha256,scan_status
  ) values (
    p_message_id,p_requester_account_id,p_original_file_name,p_content_type,p_size_bytes,
    p_storage_object_path,p_content_sha256,'Pending'
  ) returning * into v_attachment;

  return jsonb_build_object(
    'attachmentId',v_attachment.id,
    'messageId',v_attachment.message_id,
    'scanStatus',v_attachment.scan_status
  );
end
$$;

create or replace function support.finalize_user_support_attachment_scan(
    p_requester_account_id uuid,
    p_attachment_id uuid,
    p_scan_status character varying,
    p_reason_code character varying default null
) returns jsonb
language plpgsql
security definer
set search_path = support, pg_temp
as $$
declare
  v_attachment support.message_attachments%rowtype;
begin
  if p_scan_status not in ('Available','Rejected','ScanError') then
    raise exception using errcode='22023', message='support_attachment_scan_status_invalid';
  end if;
  select a.* into v_attachment
  from support.message_attachments a
  join support.conversation_messages m on m.id=a.message_id
  join support.tickets t on t.id=m.ticket_id
  where a.id=p_attachment_id and t.requester_account_id=p_requester_account_id
  for update of a;
  if not found then
    raise exception using errcode='42501', message='support_attachment_not_accessible';
  end if;
  if v_attachment.scan_status not in ('Pending','Scanning','ScanError') then
    if v_attachment.scan_status=p_scan_status and coalesce(v_attachment.scan_reason_code,'')=coalesce(p_reason_code,'') then
      return jsonb_build_object('attachmentId',v_attachment.id,'scanStatus',v_attachment.scan_status,'replayed',true);
    end if;
    raise exception using errcode='40001', message='support_attachment_scan_conflict';
  end if;
  update support.message_attachments
  set scan_status=p_scan_status,
      scan_reason_code=nullif(trim(coalesce(p_reason_code,'')),''),
      updated_at_utc=now()
  where id=p_attachment_id
  returning * into v_attachment;
  return jsonb_build_object('attachmentId',v_attachment.id,'scanStatus',v_attachment.scan_status,'replayed',false);
end
$$;

create or replace function support.get_user_support_attachment_download(
    p_requester_account_id uuid,
    p_attachment_id uuid
) returns table(
    attachment_id uuid,
    storage_object_path character varying,
    original_file_name character varying,
    content_type character varying,
    size_bytes bigint
)
language plpgsql
security definer
set search_path = support, pg_temp
as $$
begin
  return query
  select a.id,a.storage_object_path,a.original_file_name,a.content_type,a.size_bytes
  from support.message_attachments a
  join support.conversation_messages m on m.id=a.message_id
  join support.tickets t on t.id=m.ticket_id
  where a.id=p_attachment_id
    and t.requester_account_id=p_requester_account_id
    and a.scan_status='Available';
end
$$;

revoke all on function support.register_user_support_attachment(uuid,uuid,uuid,character varying,character varying,bigint,character varying,character) from public;
revoke all on function support.finalize_user_support_attachment_scan(uuid,uuid,character varying,character varying) from public;
revoke all on function support.get_user_support_attachment_download(uuid,uuid) from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant execute on function support.register_user_support_attachment(uuid,uuid,uuid,character varying,character varying,bigint,character varying,character) to lifemate_edge_runtime;
    grant execute on function support.finalize_user_support_attachment_scan(uuid,uuid,character varying,character varying) to lifemate_edge_runtime;
    grant execute on function support.get_user_support_attachment_download(uuid,uuid) to lifemate_edge_runtime;
  end if;
end
$$;
