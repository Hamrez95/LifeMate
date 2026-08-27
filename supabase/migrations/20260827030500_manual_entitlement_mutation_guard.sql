begin;

create or replace function commerce.apply_manual_entitlement_grant_guarded(
  p_actor_account_id uuid,
  p_subject_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_expires_at_utc timestamptz,
  p_adjustment_id uuid
) returns uuid[]
language plpgsql
security definer
set search_path=pg_catalog,commerce,admin,identity,pg_temp
as $$
declare
  v_target_type character varying(16):=case lower(trim(coalesce(p_target_type,'')))
    when 'product' then 'Product' when 'offer' then 'Offer' else '' end;
  v_feature uuid;
  v_entitlement_id uuid;
  v_ids uuid[]:='{}'::uuid[];
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.entitlement.adjust.execute') then
    raise exception using errcode='42501',message='entitlement_adjust_execute_permission_denied';
  end if;
  if v_target_type not in ('Product','Offer') then
    raise exception using errcode='22023',message='Invalid entitlement target type.';
  end if;
  if not exists(select 1 from identity.accounts where id=p_subject_account_id and status='Active') then
    raise exception using errcode='P0002',message='Target account is not active.';
  end if;
  if p_expires_at_utc is null or p_expires_at_utc<=now() then
    raise exception using errcode='22023',message='Grant expiry must still be in the future at execution time.';
  end if;

  for v_feature in
    select feature_id
    from commerce.manual_adjustment_target_features(v_target_type,p_target_id)
    order by feature_id
  loop
    insert into commerce.entitlements(
      grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,
      starts_at_utc,expires_at_utc,version
    ) values(
      p_subject_account_id,null,v_feature,'ADMIN_GRANT',
      'manual:'||p_adjustment_id::text||':'||v_feature::text,'Active',now(),p_expires_at_utc,1
    ) returning id into v_entitlement_id;
    v_ids:=array_append(v_ids,v_entitlement_id);
    insert into commerce.entitlement_events(
      entitlement_id,event_type,provider_event_key,occurred_at_utc,metadata_json
    ) values(
      v_entitlement_id,'Granted',
      'manual-adjustment:'||p_adjustment_id::text||':'||v_entitlement_id::text,
      now(),jsonb_build_object('adjustmentId',p_adjustment_id,'operation','Grant')
    );
  end loop;
  if cardinality(v_ids)=0 then
    raise exception using errcode='55000',message='Product or offer has no grantable entitlement features.';
  end if;
  return v_ids;
end $$;

create or replace function commerce.apply_manual_entitlement_change_guarded(
  p_actor_account_id uuid,
  p_subject_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_entitlement_id uuid,
  p_expected_version bigint,
  p_operation character varying,
  p_expires_at_utc timestamptz,
  p_adjustment_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,admin,pg_temp
as $$
declare
  v_target_type character varying(16):=case lower(trim(coalesce(p_target_type,'')))
    when 'product' then 'Product' when 'offer' then 'Offer' else '' end;
  v_operation character varying(16):=case lower(trim(coalesce(p_operation,'')))
    when 'extend' then 'Extend' when 'reduce' then 'Reduce' when 'revoke' then 'Revoke' else '' end;
  v_ent commerce.entitlements%rowtype;
  v_self_person uuid;
  v_event character varying(32);
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.entitlement.adjust.execute') then
    raise exception using errcode='42501',message='entitlement_adjust_execute_permission_denied';
  end if;
  if v_target_type not in ('Product','Offer') or v_operation not in ('Extend','Reduce','Revoke') then
    raise exception using errcode='22023',message='Invalid entitlement adjustment operation.';
  end if;
  v_self_person:=commerce.manual_adjustment_self_person(p_subject_account_id);
  select * into v_ent
  from commerce.entitlements e
  where e.id=p_entitlement_id
    and (
      e.grantee_account_id=p_subject_account_id
      or (v_self_person is not null and e.beneficiary_person_id=v_self_person)
    )
  for update;
  if not found then
    raise exception using errcode='P0002',message='Entitlement was not found for the target account.';
  end if;
  if v_ent.version<>p_expected_version then
    raise exception using errcode='40001',message='Entitlement version conflict.';
  end if;
  if v_ent.feature_id<>all(array(select feature_id from commerce.manual_adjustment_target_features(v_target_type,p_target_id))) then
    raise exception using errcode='22023',message='Entitlement feature does not belong to selected product or offer.';
  end if;
  if v_ent.source='FREE' then
    raise exception using errcode='22023',message='Free baseline entitlement cannot be manually adjusted.';
  end if;
  if v_ent.status<>'Active' or v_ent.starts_at_utc>now() or (v_ent.expires_at_utc is not null and v_ent.expires_at_utc<=now()) then
    raise exception using errcode='55000',message='Only an active entitlement can be adjusted.';
  end if;

  if v_operation='Revoke' then
    if p_expires_at_utc is null or p_expires_at_utc>now()+interval '5 minutes' then
      raise exception using errcode='22023',message='Revoke execution timestamp is invalid.';
    end if;
    update commerce.entitlements
    set status='Revoked',expires_at_utc=p_expires_at_utc,version=version+1,updated_at_utc=now()
    where id=v_ent.id;
    v_event:='Revoked';
  elsif v_operation='Reduce' then
    if p_expires_at_utc is null or p_expires_at_utc<=now()
       or (v_ent.expires_at_utc is not null and p_expires_at_utc>=v_ent.expires_at_utc) then
      raise exception using errcode='22023',message='Reduced expiry is no longer valid.';
    end if;
    update commerce.entitlements
    set expires_at_utc=p_expires_at_utc,version=version+1,updated_at_utc=now()
    where id=v_ent.id;
    v_event:='Adjusted';
  else
    if v_ent.expires_at_utc is null or p_expires_at_utc is null or p_expires_at_utc<=v_ent.expires_at_utc then
      raise exception using errcode='22023',message='Extended expiry is no longer valid.';
    end if;
    update commerce.entitlements
    set expires_at_utc=p_expires_at_utc,version=version+1,updated_at_utc=now()
    where id=v_ent.id;
    v_event:='Renewed';
  end if;

  insert into commerce.entitlement_events(
    entitlement_id,event_type,provider_event_key,occurred_at_utc,metadata_json
  ) values(
    v_ent.id,v_event,
    'manual-adjustment:'||p_adjustment_id::text||':'||v_ent.id::text,
    now(),jsonb_build_object('adjustmentId',p_adjustment_id,'operation',v_operation)
  );
  return commerce.manual_adjustment_after_state(v_ent.id);
end $$;

revoke execute on function commerce.apply_manual_entitlement_grant(uuid,character varying,uuid,timestamptz,uuid)
  from lifemate_admin_runtime;
revoke execute on function commerce.apply_manual_entitlement_change(uuid,character varying,uuid,uuid,bigint,character varying,timestamptz,uuid)
  from lifemate_admin_runtime;
revoke all on function commerce.apply_manual_entitlement_grant_guarded(uuid,uuid,character varying,uuid,timestamptz,uuid)
  from public,anon,authenticated;
revoke all on function commerce.apply_manual_entitlement_change_guarded(uuid,uuid,character varying,uuid,uuid,bigint,character varying,timestamptz,uuid)
  from public,anon,authenticated;
grant execute on function commerce.apply_manual_entitlement_grant_guarded(uuid,uuid,character varying,uuid,timestamptz,uuid)
  to lifemate_admin_runtime;
grant execute on function commerce.apply_manual_entitlement_change_guarded(uuid,uuid,character varying,uuid,uuid,bigint,character varying,timestamptz,uuid)
  to lifemate_admin_runtime;

comment on function commerce.apply_manual_entitlement_grant_guarded(uuid,uuid,character varying,uuid,timestamptz,uuid)
is 'Actor-aware mutation primitive for #492. Re-checks execute permission, active subject, target mapping and live expiry inside the database.';
comment on function commerce.apply_manual_entitlement_change_guarded(uuid,uuid,character varying,uuid,uuid,bigint,character varying,timestamptz,uuid)
is 'Actor-aware mutation primitive for #492. Re-checks execute permission, exact version, FREE protection, target membership and live expiry semantics.';

commit;
