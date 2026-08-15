-- Account deletion retention-v2
--
-- Preserve only pseudonymous compliance/audit tombstones and shared records
-- that belong to another person. Raw healthcare/women-calendar data owned by
-- the deleting person is hard-deleted. Identity/contact/provider linkages are
-- removed, app/person profiles are anonymized, and the worker-facing finalizer
-- is SECURITY DEFINER so the worker does not need broad DELETE grants.

create or replace function identity.request_account_deletion(p_account_id uuid)
returns uuid
language plpgsql
set search_path = pg_catalog, identity, core, ecosystem, network, security, commerce, integration, lifemate, pg_temp
as $$
declare
  v_request_id uuid;
  v_self_person_id uuid;
  v_app_user_id uuid;
begin
  select legacy_app_user_id
    into v_app_user_id
    from identity.accounts
   where id = p_account_id
     and status <> 'Deleted'
   for update;

  if not found then
    raise exception 'account_not_found';
  end if;

  -- Compatibility for pre-ecosystem rows. New accounts must use the explicit
  -- identity.accounts.legacy_app_user_id bridge; never assume IDs are equal.
  if v_app_user_id is null and exists (
    select 1 from lifemate.app_users where id = p_account_id
  ) then
    v_app_user_id := p_account_id;
  end if;

  select person_id
    into v_self_person_id
    from core.account_person_links
   where account_id = p_account_id
     and link_type = 'Self'
     and status = 'Active'
   limit 1;

  insert into identity.account_deletion_requests(
    account_id,status,requested_at_utc,retention_policy_version
  )
  values(p_account_id,'Requested',now(),'retention-v2')
  on conflict(account_id,status) do update
    set requested_at_utc = excluded.requested_at_utc,
        retention_policy_version = excluded.retention_policy_version
  returning id into v_request_id;

  update identity.accounts
     set status = 'DeletionPending', updated_at_utc = now()
   where id = p_account_id;

  if v_app_user_id is not null then
    update lifemate.app_users
       set status = 'Disabled', updated_at_utc = now()
     where id = v_app_user_id;
  end if;

  update identity.external_identities
     set status = 'Disabled'
   where account_id = p_account_id
     and status = 'Active';

  update ecosystem.app_enrollments
     set status = 'Suspended'
   where account_id = p_account_id
     and status = 'Active';

  if v_app_user_id is not null then
    update lifemate.care_relationships
       set status = 'Revoked',
           revoked_by_user_id = v_app_user_id,
           revoked_at_utc = coalesce(revoked_at_utc,now()),
           updated_at_utc = now()
     where status = 'Active'
       and (patient_user_id = v_app_user_id or caregiver_user_id = v_app_user_id);
  end if;

  if v_self_person_id is not null then
    update network.person_relationships
       set status = 'Ended',
           ended_at_utc = coalesce(ended_at_utc,now())
     where status = 'Active'
       and (source_person_id = v_self_person_id or target_person_id = v_self_person_id);
  end if;

  update security.access_grants
     set status = 'Revoked',
         revoked_at_utc = coalesce(revoked_at_utc,now()),
         updated_at_utc = now()
   where status = 'Active'
     and (
       grantee_account_id = p_account_id
       or (v_self_person_id is not null and subject_person_id = v_self_person_id)
     );

  update commerce.entitlements
     set status = 'Revoked', updated_at_utc = now()
   where status = 'Active'
     and (
       grantee_account_id = p_account_id
       or (v_self_person_id is not null and beneficiary_person_id = v_self_person_id)
     );

  insert into integration.outbox_messages(
    aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc
  )
  values
    ('account',p_account_id,'identity.session_revoke_requested',
     'account-deletion:session-revoke:'||v_request_id::text,
     jsonb_build_object('accountId',p_account_id,'requestId',v_request_id),'Pending',now()),
    ('account',p_account_id,'identity.account_deletion_requested',
     'account-deletion:process:'||v_request_id::text,
     jsonb_build_object('accountId',p_account_id,'requestId',v_request_id),'Pending',now())
  on conflict(idempotency_key) do nothing;

  return v_request_id;
end
$$;

create or replace function identity.finalize_account_deletion(p_request_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, identity, core, ecosystem, network, lifemate, care, pg_temp
as $$
declare
  v_account_id uuid;
  v_app_user_id uuid;
  v_person_id uuid;
  v_auth_subject text;
  v_auth_subject_uuid uuid;
  v_status varchar;
begin
  select r.account_id, r.status, a.legacy_app_user_id
    into v_account_id, v_status, v_app_user_id
    from identity.account_deletion_requests r
    join identity.accounts a on a.id = r.account_id
   where r.id = p_request_id
   for update of r, a;

  if not found then
    raise exception 'deletion_request_not_found';
  end if;

  if v_status = 'Completed' then
    return true;
  end if;

  if v_status not in ('Requested','Processing') then
    raise exception 'deletion_request_not_processable';
  end if;

  if v_app_user_id is null and exists (
    select 1 from lifemate.app_users where id = v_account_id
  ) then
    v_app_user_id := v_account_id;
  end if;

  select person_id
    into v_person_id
    from core.account_person_links
   where account_id = v_account_id
     and link_type = 'Self'
   order by case when status = 'Active' then 0 else 1 end, created_at_utc
   limit 1;

  if v_app_user_id is not null then
    select auth_subject
      into v_auth_subject
      from lifemate.app_users
     where id = v_app_user_id
     for update;

    begin
      v_auth_subject_uuid := nullif(v_auth_subject,'')::uuid;
    exception when invalid_text_representation then
      v_auth_subject_uuid := null;
    end;
  end if;

  update identity.account_deletion_requests
     set status = 'Processing',
         processing_started_at_utc = coalesce(processing_started_at_utc,now()),
         retention_policy_version = 'retention-v2'
   where id = p_request_id;

  -- Derived healthcare projections are not compliance records.
  if v_person_id is not null then
    delete from care.daily_adherence_summary
     where person_id = v_person_id;
  end if;

  -- Delete the patient's own raw healthcare data. Records belonging to another
  -- patient are intentionally not deleted merely because this account acted as
  -- caregiver/creator; those records retain only the pseudonymous app-user ID.
  if v_app_user_id is not null or v_person_id is not null then
    delete from lifemate.women_calendar_support_actions
     where (v_app_user_id is not null and patient_user_id = v_app_user_id)
        or (v_person_id is not null and patient_person_id = v_person_id);

    delete from lifemate.women_calendar_daily_logs
     where (v_app_user_id is not null and owner_user_id = v_app_user_id)
        or (v_person_id is not null and owner_person_id = v_person_id);

    delete from lifemate.women_calendar_episodes
     where (v_app_user_id is not null and owner_user_id = v_app_user_id)
        or (v_person_id is not null and owner_person_id = v_person_id);

    delete from lifemate.women_calendar_profiles
     where (v_app_user_id is not null and owner_user_id = v_app_user_id)
        or (v_person_id is not null and owner_person_id = v_person_id);

    delete from lifemate.health_observations
     where (v_app_user_id is not null and owner_user_id = v_app_user_id)
        or (v_person_id is not null and person_id = v_person_id);

    delete from lifemate.care_events
     where (v_app_user_id is not null and patient_user_id = v_app_user_id)
        or (v_person_id is not null and patient_person_id = v_person_id);

    -- Occurrences are deleted before plans. Their adherence events cascade.
    delete from lifemate.dose_occurrences o
     where (v_app_user_id is not null and o.patient_user_id = v_app_user_id)
        or (v_person_id is not null and o.patient_person_id = v_person_id)
        or exists (
          select 1
            from lifemate.treatment_plans p
           where p.id = o.treatment_plan_id
             and (
               (v_app_user_id is not null and p.patient_user_id = v_app_user_id)
               or (v_person_id is not null and p.patient_person_id = v_person_id)
             )
        );

    delete from lifemate.treatment_plans
     where (v_app_user_id is not null and patient_user_id = v_app_user_id)
        or (v_person_id is not null and patient_person_id = v_person_id);

    delete from lifemate.medications
     where (v_app_user_id is not null and owner_user_id = v_app_user_id)
        or (v_person_id is not null and owner_person_id = v_person_id);
  end if;

  -- Invitations created by the deleting account contain contact/token hashes and
  -- hints, so delete them. Invitations belonging to another inviter remain, but
  -- no longer identify the deleted responder.
  if v_app_user_id is not null then
    delete from lifemate.care_invitations
     where inviter_user_id = v_app_user_id;

    update lifemate.care_invitations
       set responded_by_user_id = null
     where responded_by_user_id = v_app_user_id;
  end if;

  -- Idempotency responses can contain serialized healthcare response bodies.
  if v_auth_subject_uuid is not null then
    delete from lifemate.idempotency_keys
     where actor_auth_subject = v_auth_subject_uuid;
  end if;

  -- Security audit events are retained as minimal evidence but are severed from
  -- the app-user tombstone and any metadata payload is redacted.
  if v_app_user_id is not null then
    update lifemate.audit_logs
       set actor_user_id = null,
           metadata_json = jsonb_build_object('redacted','account_deleted')
     where actor_user_id = v_app_user_id;
  end if;

  delete from identity.contact_points where account_id = v_account_id;
  delete from identity.external_identities where account_id = v_account_id;

  update core.account_person_links
     set status = 'Revoked',
         revoked_at_utc = coalesce(revoked_at_utc,now())
   where account_id = v_account_id;

  if v_person_id is not null then
    update core.person_profiles
       set display_name = 'Deleted user',
           locale = 'en',
           time_zone = 'UTC',
           avatar_key = 'person_blue',
           profile_photo_path = null,
           updated_at_utc = now()
     where person_id = v_person_id;

    update core.persons
       set status = 'Deleted',
           subject_category = 'Unknown',
           home_region = null,
           birth_date = null,
           updated_at_utc = now()
     where id = v_person_id;
  end if;

  if v_app_user_id is not null then
    update lifemate.user_profiles
       set display_name = 'Deleted user',
           phone_number = null,
           email = null,
           locale = 'en',
           time_zone = 'UTC',
           avatar_key = 'person_blue',
           profile_photo_path = null,
           version = version + 1,
           updated_at_utc = now()
     where user_id = v_app_user_id;

    update lifemate.app_users
       set auth_subject = 'deleted:' || v_app_user_id::text,
           status = 'Deleted',
           updated_at_utc = now()
     where id = v_app_user_id;
  end if;

  update ecosystem.app_enrollments
     set status = 'Left', last_active_at_utc = null
   where account_id = v_account_id;

  update identity.accounts
     set status = 'Deleted',
         home_region = null,
         updated_at_utc = now()
   where id = v_account_id;

  update identity.account_deletion_requests
     set status = 'Completed',
         completed_at_utc = now(),
         retention_policy_version = 'retention-v2'
   where id = p_request_id;

  return true;
end
$$;

-- The finalizer now owns the deletion transaction under a fixed search_path.
-- Keep the worker's surface narrow: it can call the function and read only the
-- identity/profile fields needed for Auth + Storage cleanup before finalization.
revoke all on function identity.finalize_account_deletion(uuid) from public;
revoke execute on function identity.finalize_account_deletion(uuid) from lifemate_edge_runtime;
grant execute on function identity.finalize_account_deletion(uuid) to lifemate_worker_runtime;

grant select on identity.accounts, identity.external_identities, lifemate.app_users, lifemate.user_profiles
  to lifemate_worker_runtime;

revoke update on lifemate.user_profiles from lifemate_worker_runtime;
revoke delete on identity.contact_points, identity.external_identities from lifemate_worker_runtime;
revoke update on identity.accounts from lifemate_worker_runtime;
revoke update on core.account_person_links, core.person_profiles, core.persons from lifemate_worker_runtime;
revoke update on ecosystem.app_enrollments from lifemate_worker_runtime;

-- No currently pending requests exist in production at migration authoring time,
-- but keep a portable upgrade path for any shared environment that does.
update identity.account_deletion_requests
   set retention_policy_version = 'retention-v2'
 where status in ('Requested','Processing');
