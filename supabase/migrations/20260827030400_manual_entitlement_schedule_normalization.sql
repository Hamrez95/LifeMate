begin;

create or replace function commerce.preview_manual_entitlement_adjustment(
  p_subject_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_entitlement_id uuid,
  p_expected_entitlement_version bigint,
  p_operation character varying,
  p_schedule_mode character varying,
  p_schedule_amount integer,
  p_exact_expires_at_utc timestamptz,
  p_reference_at_utc timestamptz
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,commerce,identity,core,pg_temp
as $$
declare
  v_operation character varying(16):=case lower(trim(coalesce(p_operation,'')))
    when 'grant' then 'Grant' when 'extend' then 'Extend' when 'reduce' then 'Reduce' when 'revoke' then 'Revoke' else '' end;
  v_target_type character varying(16):=case lower(trim(coalesce(p_target_type,'')))
    when 'product' then 'Product' when 'offer' then 'Offer' else '' end;
  v_mode character varying(24):=case lower(trim(coalesce(p_schedule_mode,'')))
    when 'exactexpiry' then 'ExactExpiry'
    when 'adddays' then 'AddDays'
    when 'addmonths' then 'AddMonths'
    when 'immediate' then 'Immediate'
    else '' end;
  v_reference timestamptz:=coalesce(p_reference_at_utc,now());
  v_ent commerce.entitlements%rowtype;
  v_self_person uuid;
  v_features uuid[];
  v_current_expiry timestamptz;
  v_effective_expiry timestamptz;
  v_before jsonb;
  v_after jsonb;
begin
  if v_target_type not in ('Product','Offer') or v_operation not in ('Grant','Extend','Reduce','Revoke')
     or v_mode not in ('ExactExpiry','AddDays','AddMonths','Immediate') then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjustment_invalid','message','Adjustment type is invalid.');
  end if;
  if not exists(select 1 from identity.accounts where id=p_subject_account_id and status='Active') then
    return jsonb_build_object('httpStatus',404,'code','entitlement_subject_not_found','message','Target account is not active.');
  end if;
  select array_agg(feature_id order by feature_id) into v_features
  from commerce.manual_adjustment_target_features(v_target_type,p_target_id);
  if coalesce(cardinality(v_features),0)=0 then
    return jsonb_build_object('httpStatus',404,'code','entitlement_target_not_found','message','Product or offer has no canonical feature mapping.');
  end if;

  if v_operation='Grant' then
    if p_entitlement_id is not null or p_expected_entitlement_version is not null then
      return jsonb_build_object('httpStatus',400,'code','entitlement_grant_existing_invalid','message','Grant does not accept an existing entitlement.');
    end if;
    if v_mode='Immediate' then
      return jsonb_build_object('httpStatus',400,'code','entitlement_grant_schedule_invalid','message','Grant requires ExactExpiry, AddDays or AddMonths.');
    end if;
    if v_mode='ExactExpiry' then
      if p_exact_expires_at_utc is null or p_exact_expires_at_utc<=v_reference then
        return jsonb_build_object('httpStatus',400,'code','entitlement_expiry_invalid','message','Exact expiry must be after reference time.');
      end if;
      v_effective_expiry:=p_exact_expires_at_utc;
    elsif v_mode='AddDays' then
      if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>3650 then
        return jsonb_build_object('httpStatus',400,'code','entitlement_days_invalid','message','AddDays amount is invalid.');
      end if;
      v_effective_expiry:=v_reference+make_interval(days=>p_schedule_amount);
    else
      if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>120 then
        return jsonb_build_object('httpStatus',400,'code','entitlement_months_invalid','message','AddMonths amount is invalid.');
      end if;
      v_effective_expiry:=v_reference+make_interval(months=>p_schedule_amount);
    end if;
    v_before:=jsonb_build_object('subjectAccountId',p_subject_account_id,'targetType',v_target_type,'targetId',p_target_id,'entitlementId',null);
    v_after:=jsonb_build_object('status','Active','featureIds',to_jsonb(v_features),'expiresAtUtc',v_effective_expiry);
  else
    if p_entitlement_id is null or p_expected_entitlement_version is null or p_expected_entitlement_version<1 then
      return jsonb_build_object('httpStatus',400,'code','entitlement_version_required','message','Existing adjustments require entitlementId and expectedEntitlementVersion.');
    end if;
    v_self_person:=commerce.manual_adjustment_self_person(p_subject_account_id);
    select * into v_ent from commerce.entitlements e
    where e.id=p_entitlement_id
      and (e.grantee_account_id=p_subject_account_id or (v_self_person is not null and e.beneficiary_person_id=v_self_person));
    if not found then
      return jsonb_build_object('httpStatus',404,'code','entitlement_not_found','message','Entitlement was not found for this account.');
    end if;
    if v_ent.version<>p_expected_entitlement_version then
      return jsonb_build_object('httpStatus',409,'code','entitlement_version_conflict','message','Entitlement changed; refresh before adjusting.','currentVersion',v_ent.version);
    end if;
    if v_ent.feature_id<>all(v_features) then
      return jsonb_build_object('httpStatus',409,'code','entitlement_target_mismatch','message','Entitlement feature is not part of the selected product/offer.');
    end if;
    if v_ent.source='FREE' then
      return jsonb_build_object('httpStatus',409,'code','free_entitlement_not_adjustable','message','Free baseline entitlement cannot be manually reduced, extended or revoked.');
    end if;
    if v_ent.status<>'Active' or v_ent.starts_at_utc>v_reference or (v_ent.expires_at_utc is not null and v_ent.expires_at_utc<=v_reference) then
      return jsonb_build_object('httpStatus',409,'code','entitlement_not_active','message','Only an active entitlement can be adjusted.');
    end if;
    v_current_expiry:=v_ent.expires_at_utc;
    if v_operation='Revoke' then
      if v_mode<>'Immediate' then return jsonb_build_object('httpStatus',400,'code','revoke_schedule_invalid','message','Revoke requires Immediate mode.'); end if;
      v_effective_expiry:=v_reference;
    elsif v_operation='Reduce' then
      if v_mode<>'ExactExpiry' or p_exact_expires_at_utc is null or p_exact_expires_at_utc<=v_reference then
        return jsonb_build_object('httpStatus',400,'code','reduce_expiry_invalid','message','Reduce requires a future exact expiry.');
      end if;
      if v_current_expiry is not null and p_exact_expires_at_utc>=v_current_expiry then
        return jsonb_build_object('httpStatus',409,'code','reduce_not_smaller','message','Reduced expiry must be earlier than current expiry.');
      end if;
      v_effective_expiry:=p_exact_expires_at_utc;
    elsif v_operation='Extend' then
      if v_current_expiry is null then return jsonb_build_object('httpStatus',409,'code','entitlement_indefinite','message','An indefinite entitlement cannot be extended.'); end if;
      if v_mode='ExactExpiry' then
        if p_exact_expires_at_utc is null then return jsonb_build_object('httpStatus',400,'code','exact_expiry_required','message','ExactExpiry requires exactExpiresAtUtc.'); end if;
        v_effective_expiry:=p_exact_expires_at_utc;
      elsif v_mode='AddDays' then
        if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>3650 then return jsonb_build_object('httpStatus',400,'code','entitlement_days_invalid','message','AddDays amount is invalid.'); end if;
        v_effective_expiry:=v_current_expiry+make_interval(days=>p_schedule_amount);
      elsif v_mode='AddMonths' then
        if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>120 then return jsonb_build_object('httpStatus',400,'code','entitlement_months_invalid','message','AddMonths amount is invalid.'); end if;
        v_effective_expiry:=v_current_expiry+make_interval(months=>p_schedule_amount);
      else return jsonb_build_object('httpStatus',400,'code','extend_schedule_invalid','message','Extend requires an expiry schedule.'); end if;
      if v_effective_expiry is null or v_effective_expiry<=v_current_expiry then return jsonb_build_object('httpStatus',409,'code','extend_not_larger','message','Extended expiry must be later than current expiry.'); end if;
    else
      return jsonb_build_object('httpStatus',400,'code','operation_invalid','message','Operation is invalid.');
    end if;
    v_before:=jsonb_build_object('entitlementId',v_ent.id,'featureId',v_ent.feature_id,'source',v_ent.source,'status',v_ent.status,'expiresAtUtc',v_ent.expires_at_utc,'version',v_ent.version);
    v_after:=jsonb_build_object('entitlementId',v_ent.id,'featureId',v_ent.feature_id,'status',case when v_operation='Revoke' then 'Revoked' else 'Active' end,'expiresAtUtc',v_effective_expiry,'version',v_ent.version+1);
  end if;

  return jsonb_build_object(
    'httpStatus',200,'code','ok','before',v_before,
    'delta',jsonb_build_object('operation',v_operation,'targetType',v_target_type,'targetId',p_target_id,'scheduleMode',v_mode,'scheduleAmount',p_schedule_amount,'exactExpiresAtUtc',p_exact_expires_at_utc,'referenceAtUtc',v_reference),
    'after',v_after
  );
end $$;

revoke all on function commerce.preview_manual_entitlement_adjustment(
  uuid,character varying,uuid,uuid,bigint,character varying,character varying,integer,timestamptz,timestamptz
) from public,anon,authenticated;
grant execute on function commerce.preview_manual_entitlement_adjustment(
  uuid,character varying,uuid,uuid,bigint,character varying,character varying,integer,timestamptz,timestamptz
) to lifemate_admin_runtime;

commit;
