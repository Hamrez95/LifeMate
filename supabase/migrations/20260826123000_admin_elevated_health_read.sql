-- Read-only elevated health projection for Command Center.
-- The runtime gets EXECUTE only; raw health tables are never granted to the Admin API role.

begin;

create or replace function admin.read_elevated_health_summary(
  p_actor_account_id uuid,
  p_subject_person_id uuid,
  p_capability character varying,
  p_correlation_id uuid,
  p_limit integer default 50
) returns jsonb
language plpgsql
security definer
set search_path = admin, lifemate, core, pg_temp
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit,50),1),50);
  v_allowed boolean;
  v_payload jsonb;
begin
  if p_capability not in ('health.read.elevated','women_health.read.elevated') then
    return jsonb_build_object('httpStatus',400,'code','elevated_capability_invalid');
  end if;

  v_allowed := admin.account_has_elevated_access(
    p_actor_account_id,
    p_subject_person_id,
    p_capability,
    now()
  );

  if not v_allowed then
    insert into admin.audit_events(
      actor_account_id,action,resource_type,resource_id,result,reason,
      correlation_id,elevated_access,metadata_json
    ) values (
      p_actor_account_id,'security.elevated_health.read','person',p_subject_person_id::text,
      'Denied','No active exact break-glass grant.',p_correlation_id,true,
      jsonb_build_object('capability',p_capability)
    );
    return jsonb_build_object('httpStatus',403,'code','elevated_access_denied');
  end if;

  if p_capability='health.read.elevated' then
    select jsonb_build_object(
      'httpStatus',200,
      'code','ok',
      'subjectPersonId',p_subject_person_id,
      'capability',p_capability,
      'observations',coalesce((
        select jsonb_agg(jsonb_build_object(
          'observationType',x.observation_type,
          'valuePrimary',x.value_primary,
          'valueSecondary',x.value_secondary,
          'unitPrimary',x.unit_primary,
          'unitSecondary',x.unit_secondary,
          'observedAtUtc',x.observed_at_utc,
          'sourceCategory',x.source_category
        ) order by x.observed_at_utc desc)
        from (
          select observation_type,value_primary,value_secondary,unit_primary,unit_secondary,
                 observed_at_utc,source_category
          from lifemate.health_observations
          where person_id=p_subject_person_id
          order by observed_at_utc desc,id desc
          limit v_limit
        ) x
      ),'[]'::jsonb),
      'medications',coalesce((
        select jsonb_agg(jsonb_build_object(
          'name',x.name,'strengthText',x.strength_text,'form',x.form,
          'updatedAtUtc',x.updated_at_utc
        ) order by x.updated_at_utc desc)
        from (
          select name,strength_text,form,updated_at_utc
          from lifemate.medications
          where owner_person_id=p_subject_person_id
          order by updated_at_utc desc,id desc
          limit v_limit
        ) x
      ),'[]'::jsonb),
      'treatmentPlans',coalesce((
        select jsonb_agg(jsonb_build_object(
          'doseText',x.dose_text,'startDate',x.start_date,'endDate',x.end_date,
          'status',x.status,'updatedAtUtc',x.updated_at_utc
        ) order by x.updated_at_utc desc)
        from (
          select dose_text,start_date,end_date,status,updated_at_utc
          from lifemate.treatment_plans
          where patient_person_id=p_subject_person_id
          order by updated_at_utc desc,id desc
          limit v_limit
        ) x
      ),'[]'::jsonb)
    ) into v_payload;
  else
    select jsonb_build_object(
      'httpStatus',200,
      'code','ok',
      'subjectPersonId',p_subject_person_id,
      'capability',p_capability,
      'episodes',coalesce((
        select jsonb_agg(jsonb_build_object(
          'startedOn',x.started_on,'endedOn',x.ended_on,'updatedAtUtc',x.updated_at_utc
        ) order by x.started_on desc)
        from (
          select started_on,ended_on,updated_at_utc
          from lifemate.women_calendar_episodes
          where owner_person_id=p_subject_person_id
          order by started_on desc,id desc
          limit v_limit
        ) x
      ),'[]'::jsonb)
    ) into v_payload;
  end if;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,elevated_access,metadata_json
  ) values (
    p_actor_account_id,'security.elevated_health.read','person',p_subject_person_id::text,
    'Allowed','Exact active break-glass grant verified.',p_correlation_id,true,
    jsonb_build_object('capability',p_capability,'limit',v_limit)
  );

  return v_payload;
end $$;

revoke all on function admin.read_elevated_health_summary(
  uuid,uuid,character varying,uuid,integer
) from public;
grant execute on function admin.read_elevated_health_summary(
  uuid,uuid,character varying,uuid,integer
) to lifemate_admin_runtime;

commit;
