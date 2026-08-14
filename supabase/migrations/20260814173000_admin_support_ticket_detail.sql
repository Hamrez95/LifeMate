-- ADM-SUP-002: privacy-minimized ticket timeline plus narrow audited write boundary.
-- Raw chat transcripts, attachments and raw health/Women Health payloads remain outside
-- Command Center support detail. Internal notes are explicitly privacy-minimized text.

create table if not exists support.ticket_events (
    id uuid primary key default gen_random_uuid(),
    ticket_id uuid not null references support.tickets(id) on delete cascade,
    event_type character varying(48) not null
        check (event_type in (
            'TicketCreated','InternalNoteAdded','StatusChanged',
            'PriorityChanged','AssigneeChanged'
        )),
    actor_account_id uuid references identity.accounts(id) on delete restrict,
    safe_summary character varying(2000),
    from_value character varying(160),
    to_value character varying(160),
    occurred_at_utc timestamp with time zone not null default now(),
    check (safe_summary is null or length(trim(safe_summary)) between 1 and 2000)
);

comment on column support.ticket_events.safe_summary is
  'Privacy-minimized support text only. Operators must not place raw health/Women Health data or unnecessary contact details here.';

create index if not exists ix_support_ticket_events_timeline
    on support.ticket_events(ticket_id, occurred_at_utc desc, id desc);

alter table support.ticket_events enable row level security;
alter table support.ticket_events force row level security;

drop policy if exists lifemate_admin_runtime_select on support.ticket_events;
create policy lifemate_admin_runtime_select
on support.ticket_events for select to lifemate_admin_runtime
using (true);

insert into support.ticket_events(
    ticket_id, event_type, actor_account_id, safe_summary, occurred_at_utc
)
select t.id, 'TicketCreated', null, null, t.created_at_utc
from support.tickets t
where not exists (
    select 1 from support.ticket_events e
    where e.ticket_id = t.id and e.event_type = 'TicketCreated'
);

create or replace view admin.support_ticket_events_v1
with (security_invoker = true)
as
select
    e.id as event_id,
    e.ticket_id,
    e.event_type,
    e.actor_account_id,
    actor_profile.display_name as actor_display_name,
    e.safe_summary,
    e.from_value,
    e.to_value,
    e.occurred_at_utc
from support.ticket_events e
left join core.account_person_links actor_link
  on actor_link.account_id = e.actor_account_id
 and actor_link.link_type = 'Self'
 and actor_link.status = 'Active'
left join core.person_profiles actor_profile
  on actor_profile.person_id = actor_link.person_id;

create or replace function admin.execute_support_ticket_action(
    p_actor_account_id uuid,
    p_ticket_id uuid,
    p_action character varying,
    p_payload jsonb,
    p_correlation_id uuid,
    p_idempotency_key character varying,
    p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, support, identity, pg_temp
as $$
declare
    v_operation constant character varying := 'support.ticket.action';
    v_existing admin.idempotency_keys%rowtype;
    v_ticket support.tickets%rowtype;
    v_response jsonb;
    v_note text;
    v_status character varying(24);
    v_priority character varying(16);
    v_assignee uuid;
    v_assignee_text text;
    v_audit_action character varying(120);
begin
    if p_action not in ('add_note','set_status','set_priority','set_assignee') then
        return jsonb_build_object(
            'httpStatus', 400,
            'code', 'invalid_support_action',
            'message', 'Support ticket action is invalid.',
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

        if v_existing.status = 'Completed' and v_existing.response_json is not null then
            return v_existing.response_json || jsonb_build_object('replayed', true);
        end if;

        return jsonb_build_object(
            'httpStatus', 409,
            'code', 'idempotency_in_progress',
            'message', 'The matching support action is still being processed.',
            'replayed', false
        );
    end if;

    insert into admin.idempotency_keys(
        actor_account_id, operation, idempotency_key, request_hash, status
    ) values (
        p_actor_account_id, v_operation, p_idempotency_key, p_request_hash, 'Processing'
    );

    if not admin.account_has_permission(p_actor_account_id, 'support.write') then
        v_response := jsonb_build_object(
            'httpStatus', 403,
            'code', 'permission_denied',
            'message', 'The required permission is not granted.',
            'replayed', false
        );
        insert into admin.audit_events(
            actor_account_id, action, resource_type, resource_id, result, reason,
            correlation_id, request_id, elevated_access, metadata_json
        ) values (
            p_actor_account_id, 'support.ticket.' || p_action, 'support_ticket',
            p_ticket_id::text, 'Denied', 'Missing support.write permission',
            p_correlation_id, p_idempotency_key, false,
            jsonb_build_object('requestedAction', p_action)
        );
        update admin.idempotency_keys
        set status='Completed', response_status=403, response_json=v_response, updated_at_utc=now()
        where actor_account_id=p_actor_account_id and operation=v_operation
          and idempotency_key=p_idempotency_key;
        return v_response;
    end if;

    select * into v_ticket
    from support.tickets
    where id = p_ticket_id
    for update;

    if not found then
        v_response := jsonb_build_object(
            'httpStatus', 404,
            'code', 'ticket_not_found',
            'message', 'Support ticket was not found.',
            'replayed', false
        );
        insert into admin.audit_events(
            actor_account_id, action, resource_type, resource_id, result, reason,
            correlation_id, request_id, elevated_access, metadata_json
        ) values (
            p_actor_account_id, 'support.ticket.' || p_action, 'support_ticket',
            p_ticket_id::text, 'Denied', 'Target support ticket not found',
            p_correlation_id, p_idempotency_key, false,
            jsonb_build_object('requestedAction', p_action)
        );
        update admin.idempotency_keys
        set status='Completed', response_status=404, response_json=v_response, updated_at_utc=now()
        where actor_account_id=p_actor_account_id and operation=v_operation
          and idempotency_key=p_idempotency_key;
        return v_response;
    end if;

    if p_action = 'add_note' then
        v_note := trim(coalesce(p_payload->>'note',''));
        if length(v_note) < 10 or length(v_note) > 2000 then
            v_response := jsonb_build_object(
                'httpStatus', 400,
                'code', 'support_note_invalid',
                'message', 'Internal note must contain between 10 and 2000 characters.',
                'replayed', false
            );
        else
            insert into support.ticket_events(
                ticket_id, event_type, actor_account_id, safe_summary
            ) values (
                p_ticket_id, 'InternalNoteAdded', p_actor_account_id, v_note
            );
            update support.tickets
            set last_activity_at_utc=now(), updated_at_utc=now()
            where id=p_ticket_id;
            v_audit_action := 'support.ticket.note.added';
        end if;

    elsif p_action = 'set_status' then
        v_status := p_payload->>'status';
        if v_status not in ('Open','Pending','WaitingOnUser','Resolved','Closed') then
            v_response := jsonb_build_object(
                'httpStatus', 400,
                'code', 'support_status_invalid',
                'message', 'Support status is invalid.',
                'replayed', false
            );
        elsif v_status = v_ticket.status then
            v_response := jsonb_build_object(
                'httpStatus', 409,
                'code', 'support_state_conflict',
                'message', 'Support ticket already has the requested status.',
                'replayed', false
            );
        elsif v_ticket.status = 'Closed' and v_status <> 'Open' then
            v_response := jsonb_build_object(
                'httpStatus', 409,
                'code', 'support_state_conflict',
                'message', 'A closed support ticket can only be reopened to Open.',
                'replayed', false
            );
        else
            update support.tickets
            set status=v_status, last_activity_at_utc=now(), updated_at_utc=now()
            where id=p_ticket_id;
            insert into support.ticket_events(
                ticket_id, event_type, actor_account_id, from_value, to_value
            ) values (
                p_ticket_id, 'StatusChanged', p_actor_account_id,
                v_ticket.status, v_status
            );
            v_audit_action := 'support.ticket.status.changed';
        end if;

    elsif p_action = 'set_priority' then
        v_priority := p_payload->>'priority';
        if v_priority not in ('Low','Normal','High','Urgent') then
            v_response := jsonb_build_object(
                'httpStatus', 400,
                'code', 'support_priority_invalid',
                'message', 'Support priority is invalid.',
                'replayed', false
            );
        elsif v_priority = v_ticket.priority then
            v_response := jsonb_build_object(
                'httpStatus', 409,
                'code', 'support_state_conflict',
                'message', 'Support ticket already has the requested priority.',
                'replayed', false
            );
        else
            update support.tickets
            set priority=v_priority, last_activity_at_utc=now(), updated_at_utc=now()
            where id=p_ticket_id;
            insert into support.ticket_events(
                ticket_id, event_type, actor_account_id, from_value, to_value
            ) values (
                p_ticket_id, 'PriorityChanged', p_actor_account_id,
                v_ticket.priority, v_priority
            );
            v_audit_action := 'support.ticket.priority.changed';
        end if;

    else
        v_assignee_text := p_payload->>'assigneeAccountId';
        if v_assignee_text is null or v_assignee_text = '' then
            v_assignee := null;
        else
            begin
                v_assignee := v_assignee_text::uuid;
            exception when invalid_text_representation then
                v_response := jsonb_build_object(
                    'httpStatus', 400,
                    'code', 'support_assignee_invalid',
                    'message', 'Support assignee is invalid.',
                    'replayed', false
                );
            end;
        end if;

        if v_response is null and v_assignee is not null and not exists (
            select 1 from admin.members m
            where m.account_id=v_assignee
              and m.status='Active'
              and admin.account_has_permission(v_assignee, 'support.read')
        ) then
            v_response := jsonb_build_object(
                'httpStatus', 400,
                'code', 'support_assignee_invalid',
                'message', 'Assignee must be an active support-capable admin member.',
                'replayed', false
            );
        elsif v_response is null and v_assignee is not distinct from v_ticket.assigned_admin_account_id then
            v_response := jsonb_build_object(
                'httpStatus', 409,
                'code', 'support_state_conflict',
                'message', 'Support ticket already has the requested assignee.',
                'replayed', false
            );
        elsif v_response is null then
            update support.tickets
            set assigned_admin_account_id=v_assignee,
                last_activity_at_utc=now(), updated_at_utc=now()
            where id=p_ticket_id;
            insert into support.ticket_events(
                ticket_id, event_type, actor_account_id, from_value, to_value
            ) values (
                p_ticket_id, 'AssigneeChanged', p_actor_account_id,
                v_ticket.assigned_admin_account_id::text, v_assignee::text
            );
            v_audit_action := 'support.ticket.assignee.changed';
        end if;
    end if;

    if v_response is not null then
        insert into admin.audit_events(
            actor_account_id, action, resource_type, resource_id, result, reason,
            correlation_id, request_id, elevated_access, metadata_json
        ) values (
            p_actor_account_id, 'support.ticket.' || p_action, 'support_ticket',
            p_ticket_id::text, 'Denied', 'Support ticket action rejected',
            p_correlation_id, p_idempotency_key, false,
            jsonb_build_object('requestedAction', p_action, 'errorCode', v_response->>'code')
        );
        update admin.idempotency_keys
        set status='Completed', response_status=(v_response->>'httpStatus')::integer,
            response_json=v_response, updated_at_utc=now()
        where actor_account_id=p_actor_account_id and operation=v_operation
          and idempotency_key=p_idempotency_key;
        return v_response;
    end if;

    insert into admin.audit_events(
        actor_account_id, action, resource_type, resource_id, result, reason,
        correlation_id, request_id, elevated_access, metadata_json
    ) values (
        p_actor_account_id, v_audit_action, 'support_ticket', p_ticket_id::text,
        'Succeeded', 'Support ticket mutation completed',
        p_correlation_id, p_idempotency_key, false,
        case
          when p_action = 'add_note' then jsonb_build_object('requestedAction', p_action)
          else jsonb_build_object('requestedAction', p_action, 'payload', p_payload)
        end
    );

    select jsonb_build_object(
        'httpStatus', 200,
        'code', 'ok',
        'ticketId', t.id,
        'status', t.status,
        'priority', t.priority,
        'assignedAdminAccountId', t.assigned_admin_account_id,
        'lastActivityAtUtc', t.last_activity_at_utc,
        'action', p_action,
        'replayed', false
    ) into v_response
    from support.tickets t
    where t.id=p_ticket_id;

    update admin.idempotency_keys
    set status='Completed', response_status=200, response_json=v_response, updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation
      and idempotency_key=p_idempotency_key;

    return v_response;
end
$$;

revoke all on support.ticket_events from public;
revoke all on admin.support_ticket_events_v1 from public;
revoke all on function admin.execute_support_ticket_action(
    uuid, uuid, character varying, jsonb, uuid, character varying, character varying
) from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on support.ticket_events from %I', v_role);
      execute format('revoke all on admin.support_ticket_events_v1 from %I', v_role);
      execute format(
        'revoke all on function admin.execute_support_ticket_action(uuid,uuid,character varying,jsonb,uuid,character varying,character varying) from %I',
        v_role
      );
    end if;
  end loop;
end
$$;

grant select on support.ticket_events to lifemate_admin_runtime;
grant select on admin.support_ticket_events_v1 to lifemate_admin_runtime;
grant execute on function admin.execute_support_ticket_action(
    uuid, uuid, character varying, jsonb, uuid, character varying, character varying
) to lifemate_admin_runtime;

comment on view admin.support_ticket_events_v1 is
  'Privacy-minimized support ticket timeline read model for the LifeMate Command Center.';
comment on function admin.execute_support_ticket_action(
    uuid, uuid, character varying, jsonb, uuid, character varying, character varying
) is
  'Audited, idempotent support ticket mutation boundary; note text is excluded from admin audit metadata.';
