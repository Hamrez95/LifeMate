-- Canonical Command Center lifecycle mutations for existing Access Grants.
-- Relationship, Consent and Access Grant remain separate concepts. This workflow
-- never creates a grant, never infers scopes from a relationship, and never permits
-- scope expansion. HEALTH/HIGHLY_SENSITIVE grants cannot be extended here.

begin;

alter table security.access_grants
  add column if not exists version integer not null default 1
  check (version >= 1);

insert into admin.permissions(code, domain, risk_level, role_assignable, description)
values (
  'relationships.access_grant.write',
  'relationships',
  'HIGH_RISK',
  true,
  'Narrow, revoke, or boundedly extend existing non-health Access Grants through audited workflows; never create or expand grants'
)
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id, permission_code)
select id, 'relationships.access_grant.write'
from admin.roles
where code in ('founder','super_admin') and status='Active'
on conflict do nothing;

create or replace function admin.mutate_access_grant(
  p_actor_account_id uuid,
  p_grant_id uuid,
  p_action character varying,
  p_expected_version integer,
  p_expires_at_utc timestamp with time zone,
  p_scopes character varying[],
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path = admin, security, identity, pg_temp
as $$
declare
  v_action character varying(32) := lower(trim(coalesce(p_action,'')));
  v_operation character varying(120);
  v_existing admin.idempotency_keys%rowtype;
  v_grant security.access_grants%rowtype;
  v_before_scope_count integer := 0;
  v_after_scope_count integer := 0;
  v_missing_scope_count integer := 0;
  v_sensitive_scope_count integer := 0;
  v_response jsonb;
  v_noop boolean := false;
  v_new_version integer;
begin
  v_operation := 'relationships.access_grant.' || v_action;

  if not admin.account_has_permission(
    p_actor_account_id,
    'relationships.access_grant.write'
  ) then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,v_operation,'access_grant',p_grant_id::text,'Denied',
      'The required Access Grant mutation permission is not granted.',
      p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('code','permission_denied')
    );
    return jsonb_build_object(
      'httpStatus',403,'code','permission_denied',
      'message','The required permission is not granted.','replayed',false
    );
  end if;

  if v_action not in ('extend','replace-scopes','revoke') then
    return jsonb_build_object(
      'httpStatus',400,'code','access_grant_action_invalid',
      'message','Access Grant action is invalid.','replayed',false
    );
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object(
      'httpStatus',400,'code','access_grant_version_invalid',
      'message','A positive expected version is required.','replayed',false
    );
  end if;
  if p_reason is null or length(trim(p_reason)) < 10 or length(trim(p_reason)) > 1000 then
    return jsonb_build_object(
      'httpStatus',400,'code','access_grant_reason_invalid',
      'message','A reason between 10 and 1000 characters is required.','replayed',false
    );
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) < 32 or length(p_request_hash) > 128 then
    return jsonb_build_object(
      'httpStatus',400,'code','idempotency_invalid',
      'message','Idempotency metadata is invalid.','replayed',false
    );
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,
      0
    )
  );
  select * into v_existing
  from admin.idempotency_keys
  where actor_account_id=p_actor_account_id
    and operation=v_operation
    and idempotency_key=p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object(
        'httpStatus',409,'code','idempotency_conflict',
        'message','This Idempotency-Key was already used for a different request.',
        'replayed',false
      );
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object(
      'httpStatus',409,'code','idempotency_in_progress',
      'message','The matching request is still being processed.','replayed',false
    );
  end if;

  insert into admin.idempotency_keys(
    actor_account_id,operation,idempotency_key,request_hash,status
  ) values (
    p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing'
  );

  perform pg_advisory_xact_lock(hashtextextended('access_grant:' || p_grant_id::text, 0));
  select * into v_grant
  from security.access_grants
  where id=p_grant_id
  for update;

  if v_grant.id is null then
    v_response := jsonb_build_object(
      'httpStatus',404,'code','access_grant_not_found',
      'message','Access Grant was not found.','replayed',false
    );
  elsif v_grant.grantee_account_id = p_actor_account_id then
    v_response := jsonb_build_object(
      'httpStatus',403,'code','access_grant_self_mutation_denied',
      'message','Administrators cannot mutate an Access Grant assigned to themselves.',
      'replayed',false
    );
  elsif v_grant.version <> p_expected_version then
    v_response := jsonb_build_object(
      'httpStatus',409,'code','access_grant_version_conflict',
      'message','Access Grant changed since it was read.',
      'version',v_grant.version,'replayed',false
    );
  else
    select count(*)::integer into v_before_scope_count
    from security.access_grant_scopes
    where grant_id=p_grant_id;

    if v_action='revoke' then
      if v_grant.status='Revoked' then
        v_noop := true;
        v_new_version := v_grant.version;
      elsif v_grant.status='Expired' then
        v_noop := true;
        v_new_version := v_grant.version;
      else
        update security.access_grants
        set status='Revoked',revoked_at_utc=now(),updated_at_utc=now(),version=version+1
        where id=p_grant_id
        returning version into v_new_version;
      end if;

    elsif v_grant.status <> 'Active' then
      v_response := jsonb_build_object(
        'httpStatus',409,'code','access_grant_not_active',
        'message','Only an active Access Grant can be changed.','replayed',false
      );

    elsif v_action='extend' then
      if p_expires_at_utc is null then
        v_response := jsonb_build_object(
          'httpStatus',400,'code','access_grant_expiry_required',
          'message','A new expiry is required.','replayed',false
        );
      elsif v_grant.expires_at_utc is null then
        v_response := jsonb_build_object(
          'httpStatus',409,'code','access_grant_indefinite_not_extendable',
          'message','An Access Grant without expiry cannot be extended.','replayed',false
        );
      elsif p_expires_at_utc <= v_grant.expires_at_utc then
        v_response := jsonb_build_object(
          'httpStatus',409,'code','access_grant_expiry_not_extended',
          'message','New expiry must be later than the current expiry.','replayed',false
        );
      elsif p_expires_at_utc > now() + interval '90 days' then
        v_response := jsonb_build_object(
          'httpStatus',403,'code','access_grant_extension_window_denied',
          'message','Admin extensions are limited to a 90-day horizon.','replayed',false
        );
      else
        select count(*)::integer into v_sensitive_scope_count
        from security.access_grant_scopes gs
        join security.scope_catalog sc on sc.scope=gs.scope
        where gs.grant_id=p_grant_id
          and sc.sensitivity in ('HEALTH','HIGHLY_SENSITIVE');
        if v_sensitive_scope_count > 0 then
          v_response := jsonb_build_object(
            'httpStatus',403,'code','access_grant_sensitive_extension_denied',
            'message','Health-sensitive Access Grants cannot be extended through the Admin lifecycle workflow.',
            'replayed',false
          );
        else
          update security.access_grants
          set expires_at_utc=p_expires_at_utc,updated_at_utc=now(),version=version+1
          where id=p_grant_id
          returning version into v_new_version;
        end if;
      end if;

    else
      if p_scopes is null or cardinality(p_scopes) < 1 or cardinality(p_scopes) > 100 then
        v_response := jsonb_build_object(
          'httpStatus',400,'code','access_grant_scopes_invalid',
          'message','A bounded non-empty scope set is required.','replayed',false
        );
      elsif cardinality(p_scopes) <> (
        select count(distinct scope) from unnest(p_scopes) as requested(scope)
      ) then
        v_response := jsonb_build_object(
          'httpStatus',400,'code','access_grant_scope_duplicate',
          'message','Access Grant scopes must be unique.','replayed',false
        );
      else
        select count(*)::integer into v_missing_scope_count
        from unnest(p_scopes) as requested(scope)
        left join security.scope_catalog sc on sc.scope=requested.scope
        where sc.scope is null;
        if v_missing_scope_count > 0 then
          v_response := jsonb_build_object(
            'httpStatus',400,'code','access_grant_scope_unknown',
            'message','One or more requested scopes are not canonical.','replayed',false
          );
        else
          select count(*)::integer into v_missing_scope_count
          from unnest(p_scopes) as requested(scope)
          left join security.access_grant_scopes current_scope
            on current_scope.grant_id=p_grant_id
           and current_scope.scope=requested.scope
          where current_scope.scope is null;
          if v_missing_scope_count > 0 then
            v_response := jsonb_build_object(
              'httpStatus',403,'code','access_grant_scope_escalation_denied',
              'message','This workflow may narrow scopes but cannot add access.',
              'replayed',false
            );
          else
            select cardinality(p_scopes) into v_after_scope_count;
            if v_after_scope_count = v_before_scope_count then
              v_noop := true;
              v_new_version := v_grant.version;
            else
              delete from security.access_grant_scopes
              where grant_id=p_grant_id and not (scope = any(p_scopes));
              update security.access_grants
              set updated_at_utc=now(),version=version+1
              where id=p_grant_id
              returning version into v_new_version;
            end if;
          end if;
        end if;
      end if;
    end if;

    if v_response is null then
      select count(*)::integer into v_after_scope_count
      from security.access_grant_scopes
      where grant_id=p_grant_id;
      select status, expires_at_utc into v_grant.status, v_grant.expires_at_utc
      from security.access_grants where id=p_grant_id;
      insert into admin.audit_events(
        actor_account_id,action,resource_type,resource_id,result,reason,
        correlation_id,request_id,elevated_access,metadata_json
      ) values (
        p_actor_account_id,v_operation,'access_grant',p_grant_id::text,'Succeeded',
        trim(p_reason),p_correlation_id,p_idempotency_key,false,
        jsonb_build_object(
          'previousVersion',p_expected_version,
          'version',v_new_version,
          'beforeScopeCount',v_before_scope_count,
          'afterScopeCount',v_after_scope_count,
          'scopeExpansion',false,
          'noop',v_noop
        )
      );
      v_response := jsonb_build_object(
        'httpStatus',200,'code','ok','grantId',p_grant_id,
        'action',v_action,'status',v_grant.status,'version',v_new_version,
        'expiresAtUtc',v_grant.expires_at_utc,'scopeCount',v_after_scope_count,
        'noop',v_noop,'replayed',false
      );
    end if;
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,request_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,v_operation,'access_grant',p_grant_id::text,'Denied',
      coalesce(v_response->>'message','Access Grant mutation denied.'),
      p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('code',v_response->>'code')
    );
  end if;

  update admin.idempotency_keys
  set status='Completed',
      response_status=(v_response->>'httpStatus')::integer,
      response_json=v_response,
      updated_at_utc=now()
  where actor_account_id=p_actor_account_id
    and operation=v_operation
    and idempotency_key=p_idempotency_key;

  return v_response;
end $$;

revoke all on function admin.mutate_access_grant(
  uuid,uuid,character varying,integer,timestamp with time zone,character varying[],
  character varying,uuid,character varying,character varying
) from public;

grant execute on function admin.mutate_access_grant(
  uuid,uuid,character varying,integer,timestamp with time zone,character varying[],
  character varying,uuid,character varying,character varying
) to lifemate_admin_runtime;

commit;
