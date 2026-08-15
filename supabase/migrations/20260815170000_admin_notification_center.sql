-- ADM-PLAT-003: privacy-minimized, permission-aware Command Center notification state.
--
-- This migration does NOT create a generic event/log browser. It only adds per-admin
-- read receipts, a metadata-only operations snapshot, and a narrow idempotent read-state
-- mutation. Notification source adapters remain responsible for permission checks and
-- for exposing only approved redacted fields.

create table if not exists admin.notification_read_receipts (
    actor_account_id uuid not null references admin.members(account_id) on delete cascade,
    alert_key character varying(180) not null,
    source_domain character varying(24) not null
        check (source_domain in ('support','security','operations','finance','product')),
    read_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    primary key (actor_account_id, alert_key),
    check (alert_key ~ '^[a-z][a-z0-9._:-]{2,179}$')
);

create index if not exists ix_admin_notification_receipts_actor_read
    on admin.notification_read_receipts(actor_account_id, read_at_utc desc);

alter table admin.notification_read_receipts enable row level security;
alter table admin.notification_read_receipts force row level security;

drop policy if exists lifemate_admin_runtime_select on admin.notification_read_receipts;
create policy lifemate_admin_runtime_select
on admin.notification_read_receipts for select to lifemate_admin_runtime
using (true);

revoke all on admin.notification_read_receipts from public;
do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on admin.notification_read_receipts from %I', v_role);
    end if;
  end loop;
end
$$;

grant select on admin.notification_read_receipts to lifemate_admin_runtime;

comment on table admin.notification_read_receipts is
  'Per-admin Command Center notification read state only. No source payload, PHI, query text or secret material is stored here.';

-- Metadata-only queue health snapshot for the Operations notification adapter.
-- SECURITY DEFINER intentionally avoids granting the Admin runtime direct access to
-- integration.outbox_messages, whose payload_json can contain sensitive identifiers.
create or replace function admin.notification_operations_queue_snapshot()
returns table(
    ready_count bigint,
    processing_count bigint,
    dead_letter_count bigint,
    oldest_ready_age_seconds bigint,
    stale_processing_count bigint,
    latest_dead_lettered_at_utc timestamp with time zone,
    latest_stale_lock_at_utc timestamp with time zone,
    measured_at_utc timestamp with time zone
)
language sql
stable
security definer
set search_path = admin, integration, pg_temp
as $$
  select
    count(*) filter (
      where status in ('Pending','Failed') and available_at_utc <= now()
    )::bigint as ready_count,
    count(*) filter (where status='Processing')::bigint as processing_count,
    count(*) filter (where status='DeadLetter')::bigint as dead_letter_count,
    coalesce(
      extract(epoch from (
        now() - min(created_at_utc) filter (
          where status in ('Pending','Failed') and available_at_utc <= now()
        )
      ))::bigint,
      0
    ) as oldest_ready_age_seconds,
    count(*) filter (
      where status='Processing'
        and locked_at_utc is not null
        and locked_at_utc < now() - interval '10 minutes'
    )::bigint as stale_processing_count,
    max(dead_lettered_at_utc) filter (where status='DeadLetter')
      as latest_dead_lettered_at_utc,
    max(locked_at_utc) filter (
      where status='Processing'
        and locked_at_utc is not null
        and locked_at_utc < now() - interval '10 minutes'
    ) as latest_stale_lock_at_utc,
    now() as measured_at_utc
  from integration.outbox_messages
$$;

revoke all on function admin.notification_operations_queue_snapshot() from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on function admin.notification_operations_queue_snapshot() from anon;
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on function admin.notification_operations_queue_snapshot() from authenticated;
  end if;
end
$$;
grant execute on function admin.notification_operations_queue_snapshot()
  to lifemate_admin_runtime;

comment on function admin.notification_operations_queue_snapshot() is
  'Metadata-only outbox health projection for operations.read alerts. Never returns event types, resource ids or payload_json.';

-- Narrow idempotent read/unread state mutation. Source business state is never changed.
create or replace function admin.set_notification_read_state(
    p_actor_account_id uuid,
    p_alert_key character varying,
    p_source_domain character varying,
    p_read boolean,
    p_correlation_id uuid,
    p_idempotency_key character varying,
    p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, pg_temp
as $$
declare
    v_operation constant character varying := 'notification.read_state';
    v_existing admin.idempotency_keys%rowtype;
    v_permission character varying(128);
    v_response jsonb;
    v_read_at timestamp with time zone;
begin
    v_permission := case p_source_domain
      when 'support' then 'support.read'
      when 'security' then 'security.audit.read'
      when 'operations' then 'operations.read'
      when 'finance' then 'finance.read'
      when 'product' then 'analytics.read'
      else null
    end;

    if v_permission is null
       or p_alert_key is null
       or length(p_alert_key) < 3
       or length(p_alert_key) > 180
       or p_alert_key !~ '^[a-z][a-z0-9._:-]{2,179}$'
       or p_alert_key not like p_source_domain || ':%' then
      return jsonb_build_object(
        'httpStatus', 400,
        'code', 'notification_state_invalid',
        'message', 'Notification read-state request is invalid.',
        'replayed', false
      );
    end if;

    if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
       or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
      return jsonb_build_object(
        'httpStatus', 400,
        'code', 'idempotency_invalid',
        'message', 'Idempotency metadata is invalid.',
        'replayed', false
      );
    end if;

    perform pg_advisory_xact_lock(
      hashtextextended(p_actor_account_id::text || ':' || p_idempotency_key, 0)
    );

    select * into v_existing
    from admin.idempotency_keys
    where actor_account_id = p_actor_account_id
      and operation = v_operation
      and idempotency_key = p_idempotency_key
    for update;

    if found then
      if v_existing.request_hash <> p_request_hash then
        return jsonb_build_object(
          'httpStatus', 409,
          'code', 'idempotency_conflict',
          'message', 'This Idempotency-Key was already used for a different request.',
          'replayed', false
        );
      end if;
      if v_existing.status='Completed' and v_existing.response_json is not null then
        return v_existing.response_json || jsonb_build_object('replayed', true);
      end if;
      return jsonb_build_object(
        'httpStatus', 409,
        'code', 'idempotency_in_progress',
        'message', 'The matching notification update is still processing.',
        'replayed', false
      );
    end if;

    insert into admin.idempotency_keys(
      actor_account_id, operation, idempotency_key, request_hash, status
    ) values (
      p_actor_account_id, v_operation, p_idempotency_key, p_request_hash, 'Processing'
    );

    if not admin.account_has_permission(p_actor_account_id, v_permission) then
      v_response := jsonb_build_object(
        'httpStatus', 403,
        'code', 'permission_denied',
        'message', 'The required notification source permission is not granted.',
        'replayed', false
      );
      insert into admin.audit_events(
        actor_account_id, action, resource_type, resource_id, result, reason,
        correlation_id, request_id, elevated_access, metadata_json
      ) values (
        p_actor_account_id,
        case when p_read then 'notification.mark_read' else 'notification.mark_unread' end,
        'admin_notification', p_alert_key, 'Denied',
        'Missing ' || v_permission || ' permission',
        p_correlation_id, p_idempotency_key, false,
        jsonb_build_object('source', p_source_domain)
      );
      update admin.idempotency_keys
      set status='Completed', response_status=403, response_json=v_response,
          updated_at_utc=now()
      where actor_account_id=p_actor_account_id and operation=v_operation
        and idempotency_key=p_idempotency_key;
      return v_response;
    end if;

    if p_read then
      insert into admin.notification_read_receipts(
        actor_account_id, alert_key, source_domain, read_at_utc, updated_at_utc
      ) values (
        p_actor_account_id, p_alert_key, p_source_domain, now(), now()
      )
      on conflict(actor_account_id, alert_key) do update set
        source_domain=excluded.source_domain,
        read_at_utc=excluded.read_at_utc,
        updated_at_utc=now()
      returning read_at_utc into v_read_at;
    else
      delete from admin.notification_read_receipts
      where actor_account_id=p_actor_account_id and alert_key=p_alert_key;
      v_read_at := null;
    end if;

    insert into admin.audit_events(
      actor_account_id, action, resource_type, resource_id, result, reason,
      correlation_id, request_id, elevated_access, metadata_json
    ) values (
      p_actor_account_id,
      case when p_read then 'notification.mark_read' else 'notification.mark_unread' end,
      'admin_notification', p_alert_key, 'Succeeded',
      'Command Center notification presentation state updated',
      p_correlation_id, p_idempotency_key, false,
      jsonb_build_object('source', p_source_domain)
    );

    v_response := jsonb_build_object(
      'httpStatus', 200,
      'code', 'ok',
      'alertKey', p_alert_key,
      'source', p_source_domain,
      'read', p_read,
      'readAtUtc', v_read_at,
      'replayed', false
    );

    update admin.idempotency_keys
    set status='Completed', response_status=200, response_json=v_response,
        updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation
      and idempotency_key=p_idempotency_key;

    return v_response;
end
$$;

revoke all on function admin.set_notification_read_state(
  uuid, character varying, character varying, boolean, uuid,
  character varying, character varying
) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on function admin.set_notification_read_state(
      uuid, character varying, character varying, boolean, uuid,
      character varying, character varying
    ) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on function admin.set_notification_read_state(
      uuid, character varying, character varying, boolean, uuid,
      character varying, character varying
    ) from authenticated;
  end if;
end
$$;
grant execute on function admin.set_notification_read_state(
  uuid, character varying, character varying, boolean, uuid,
  character varying, character varying
) to lifemate_admin_runtime;

comment on function admin.set_notification_read_state(
  uuid, character varying, character varying, boolean, uuid,
  character varying, character varying
) is 'Idempotent permission-checked per-admin notification read/unread state mutation with immutable audit evidence; never mutates source business state.';
