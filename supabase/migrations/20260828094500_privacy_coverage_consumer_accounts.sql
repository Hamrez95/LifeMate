begin;

-- Legal acceptance coverage is a consumer/user metric. Workforce-only Admin
-- identities can exist in identity.accounts without a Self person and must not
-- depress the denominator.
create or replace function consent.admin_acceptance_coverage(
  p_actor_account_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,consent,identity,core,admin
as $$
declare
  v_result jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.consent.read',now()) then
    raise exception 'privacy_coverage_forbidden' using errcode='42501';
  end if;

  with eligible as (
    select count(*)::integer as account_count
    from identity.accounts a
    where a.status='Active'
      and exists (
        select 1
        from core.account_person_links l
        where l.account_id=a.id
          and l.link_type='Self'
          and l.status='Active'
      )
  ), required_docs as (
    select * from consent.current_registration_legal_documents(p_jurisdiction)
  ), coverage as (
    select
      d.id,
      d.purpose,
      d.version,
      d.jurisdiction,
      d.title,
      d.document_hash,
      d.effective_at_utc,
      count(distinct a.account_id) filter (
        where exists (
          select 1
          from core.account_person_links l
          where l.account_id=a.account_id
            and l.link_type='Self'
            and l.status='Active'
        )
      )::integer as accepted_count
    from required_docs d
    left join consent.legal_acceptances a
      on a.document_id=d.id and a.document_hash=d.document_hash
    group by d.id,d.purpose,d.version,d.jurisdiction,d.title,d.document_hash,d.effective_at_utc
  )
  select jsonb_build_object(
    'jurisdiction',p_jurisdiction,
    'eligibleAccountCount',e.account_count,
    'requiredDocumentCount',(select count(*) from coverage),
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'documentId',c.id,
        'purpose',c.purpose,
        'version',c.version,
        'jurisdiction',c.jurisdiction,
        'title',c.title,
        'documentHash',c.document_hash,
        'effectiveAtUtc',c.effective_at_utc,
        'acceptedAccountCount',c.accepted_count,
        'coveragePercent',case when e.account_count=0 then 0
          else round((c.accepted_count::numeric/e.account_count::numeric)*100,2) end
      ) order by c.purpose,c.version)
      from coverage c
    ),'[]'::jsonb)
  ) into v_result
  from eligible e;

  return v_result;
end
$$;

commit;
