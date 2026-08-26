-- Caregivers may manage schedules only after explicit patient opt-in.
-- Existing relationships remain read-only by default.

alter table lifemate.care_relationships
  add column if not exists can_manage_care_schedule boolean not null default false;

-- Keep contextual write scopes synchronized with the owner-controlled flag.
create or replace function security.sync_care_schedule_write_scopes(
  p_relationship_id uuid,
  p_enabled boolean
) returns void
language plpgsql
security definer
set search_path = security, lifemate, identity, pg_temp
as $$
declare
  v_grant_id uuid;
begin
  select g.id into v_grant_id
  from security.access_grants g
  join lifemate.care_relationships r on r.id = g.context_id
  where g.context_type = 'care_relationship'
    and g.context_id = p_relationship_id
    and g.status = 'Active'
    and r.status = 'Active'
  limit 1;

  if v_grant_id is null then
    if p_enabled then
      raise exception 'active contextual care grant is required';
    end if;
    return;
  end if;

  if p_enabled then
    insert into security.access_grant_scopes(grant_id, scope)
    values
      (v_grant_id, 'treatment.medication.write'),
      (v_grant_id, 'treatment.plan.write'),
      (v_grant_id, 'care.events.write')
    on conflict do nothing;
  else
    delete from security.access_grant_scopes
    where grant_id = v_grant_id
      and scope in (
        'treatment.medication.write',
        'treatment.plan.write',
        'care.events.write'
      );
  end if;
end
$$;

revoke all on function security.sync_care_schedule_write_scopes(uuid, boolean) from public;

-- Defensive reconciliation: no pre-existing relationship receives new write
-- authority merely because this migration is applied.
delete from security.access_grant_scopes s
using security.access_grants g, lifemate.care_relationships r
where s.grant_id = g.id
  and g.context_type = 'care_relationship'
  and g.context_id = r.id
  and coalesce(r.can_manage_care_schedule, false) = false
  and s.scope in (
    'treatment.medication.write',
    'treatment.plan.write',
    'care.events.write'
  );
