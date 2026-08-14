-- ADM-USR-003: audited suspend/restore boundary for ordinary end-user accounts.
-- The Admin API runtime keeps SELECT-only access to identity.accounts and receives
-- EXECUTE on this narrow SECURITY DEFINER function instead of direct UPDATE rights.

create or replace function admin.execute_user_account_action(
    p_actor_account_id uuid,
    p_target_account_id uuid,
    p_action character varying,
    p_reason character varying,
    p_correlation_id uuid,
    p_idempotency_key character varying,
    p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, identity, pg_temp
as $$
declare
    v_operation constant character varying := 'user.account.action';
    v_existing admin.idempotency_keys%rowtype;
    v_previous_status character varying(32);
    v_next_status character varying(32);
    v_response jsonb;
    v_audit_reason character varying(1000);
begin
    if p_action not in ('suspend','restore') then
        return jsonb_build_object(
            'httpStatus', 400,
            'code', 'invalid_user_action',
            'message', 'User account action is invalid.',
            'replayed', false
        );
    end if;

    if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
        return jsonb_build_object(
            'httpStatus', 400,
            'code', 'action_reason_invalid',
            'message', 'A reason between 10 and 1000 characters is required.',
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
            'message', 'The matching user action is still being processed.',
            'replayed', false
        );
    end if;

    insert into admin.idempotency_keys(
        actor_account_id, operation, idempotency_key, request_hash, status
    ) values (
        p_actor_account_id, v_operation, p_idempotency_key, p_request_hash, 'Processing'
    );

    if not admin.account_has_permission(p_actor_account_id, 'users.suspend') then
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
            p_actor_account_id, 'user.account.' || p_action, 'identity_account',
            p_target_account_id::text, 'Denied', 'Missing users.suspend permission',
            p_correlation_id, p_idempotency_key, false,
            jsonb_build_object('requestedAction', p_action)
        );
        update admin.idempotency_keys
        set status='Completed', response_status=403, response_json=v_response, updated_at_utc=now()
        where actor_account_id=p_actor_account_id and operation=v_operation
          and idempotency_key=p_idempotency_key;
        return v_response;
    end if;

    if p_actor_account_id = p_target_account_id then
        v_response := jsonb_build_object(
            'httpStatus', 409,
            'code', 'self_target_denied',
            'message', 'An administrator cannot suspend or restore their own account here.',
            'replayed', false
        );
        insert into admin.audit_events(
            actor_account_id, action, resource_type, resource_id, result, reason,
            correlation_id, request_id, elevated_access, metadata_json
        ) values (
            p_actor_account_id, 'user.account.' || p_action, 'identity_account',
            p_target_account_id::text, 'Denied', 'Self-target action denied',
            p_correlation_id, p_idempotency_key, false,
            jsonb_build_object('requestedAction', p_action)
        );
        update admin.idempotency_keys
        set status='Completed', response_status=409, response_json=v_response, updated_at_utc=now()
        where actor_account_id=p_actor_account_id and operation=v_operation
          and idempotency_key=p_idempotency_key;
        return v_response;
    end if;

    if exists (
        select 1 from admin.members
        where account_id = p_target_account_id and status = 'Active'
    ) then
        v_response := jsonb_build_object(
            'httpStatus', 409,
            'code', 'admin_target_denied',
            'message', 'Active Command Center members must be managed through the admin-membership workflow.',
            'replayed', false
        );
        insert into admin.audit_events(
            actor_account_id, action, resource_type, resource_id, result, reason,
            correlation_id, request_id, elevated_access, metadata_json
        ) values (
            p_actor_account_id, 'user.account.' || p_action, 'identity_account',
            p_target_account_id::text, 'Denied', 'Privileged admin target denied',
            p_correlation_id, p_idempotency_key, false,
            jsonb_build_object('requestedAction', p_action)
        );
        update admin.idempotency_keys
        set status='Completed', response_status=409, response_json=v_response, updated_at_utc=now()
        where actor_account_id=p_actor_account_id and operation=v_operation
          and idempotency_key=p_idempotency_key;
        return v_response;
    end if;

    select status into v_previous_status
    from identity.accounts
    where id = p_target_account_id
    for update;

    if not found then
        v_response := jsonb_build_object(
            'httpStatus', 404,
            'code', 'user_not_found',
            'message', 'User was not found.',
            'replayed', false
        );
        insert into admin.audit_events(
            actor_account_id, action, resource_type, resource_id, result, reason,
            correlation_id, request_id, elevated_access, metadata_json
        ) values (
            p_actor_account_id, 'user.account.' || p_action, 'identity_account',
            p_target_account_id::text, 'Denied', 'Target account not found',
            p_correlation_id, p_idempotency_key, false,
            jsonb_build_object('requestedAction', p_action)
        );
        update admin.idempotency_keys
        set status='Completed', response_status=404, response_json=v_response, updated_at_utc=now()
        where actor_account_id=p_actor_account_id and operation=v_operation
          and idempotency_key=p_idempotency_key;
        return v_response;
    end if;

    if p_action = 'suspend' then
        v_next_status := 'Disabled';
        if v_previous_status <> 'Active' then
            v_response := jsonb_build_object(
                'httpStatus', 409,
                'code', 'invalid_account_transition',
                'message', 'Only an active account can be suspended.',
                'accountId', p_target_account_id,
                'status', v_previous_status,
                'replayed', false
            );
        end if;
    else
        v_next_status := 'Active';
        if v_previous_status <> 'Disabled' then
            v_response := jsonb_build_object(
                'httpStatus', 409,
                'code', 'invalid_account_transition',
                'message', 'Only a disabled account can be restored.',
                'accountId', p_target_account_id,
                'status', v_previous_status,
                'replayed', false
            );
        end if;
    end if;

    if v_response is not null then
        insert into admin.audit_events(
            actor_account_id, action, resource_type, resource_id, result, reason,
            correlation_id, request_id, elevated_access, metadata_json
        ) values (
            p_actor_account_id, 'user.account.' || p_action, 'identity_account',
            p_target_account_id::text, 'Denied', 'Invalid account state transition',
            p_correlation_id, p_idempotency_key, false,
            jsonb_build_object(
                'requestedAction', p_action,
                'previousStatus', v_previous_status
            )
        );
        update admin.idempotency_keys
        set status='Completed', response_status=409, response_json=v_response, updated_at_utc=now()
        where actor_account_id=p_actor_account_id and operation=v_operation
          and idempotency_key=p_idempotency_key;
        return v_response;
    end if;

    update identity.accounts
    set status = v_next_status,
        updated_at_utc = now()
    where id = p_target_account_id;

    v_audit_reason := trim(p_reason);
    insert into admin.audit_events(
        actor_account_id, action, resource_type, resource_id, result, reason,
        correlation_id, request_id, elevated_access, metadata_json
    ) values (
        p_actor_account_id, 'user.account.' || p_action, 'identity_account',
        p_target_account_id::text, 'Succeeded', v_audit_reason,
        p_correlation_id, p_idempotency_key, false,
        jsonb_build_object(
            'requestedAction', p_action,
            'previousStatus', v_previous_status,
            'newStatus', v_next_status
        )
    );

    v_response := jsonb_build_object(
        'httpStatus', 200,
        'code', 'ok',
        'accountId', p_target_account_id,
        'previousStatus', v_previous_status,
        'status', v_next_status,
        'action', p_action,
        'replayed', false
    );

    update admin.idempotency_keys
    set status='Completed', response_status=200, response_json=v_response, updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation
      and idempotency_key=p_idempotency_key;

    return v_response;
end
$$;

revoke all on function admin.execute_user_account_action(
    uuid, uuid, character varying, character varying, uuid, character varying, character varying
) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname='anon') then
        revoke all on function admin.execute_user_account_action(
            uuid, uuid, character varying, character varying, uuid, character varying, character varying
        ) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then
        revoke all on function admin.execute_user_account_action(
            uuid, uuid, character varying, character varying, uuid, character varying, character varying
        ) from authenticated;
    end if;
end
$$;

grant execute on function admin.execute_user_account_action(
    uuid, uuid, character varying, character varying, uuid, character varying, character varying
) to lifemate_admin_runtime;

comment on function admin.execute_user_account_action(
    uuid, uuid, character varying, character varying, uuid, character varying, character varying
) is 'Audited, idempotent, permission-checked suspend/restore boundary for ordinary LifeMate end-user accounts.';
