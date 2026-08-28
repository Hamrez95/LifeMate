begin;

-- Raw user-authored feedback may contain sensitive free text. Keep the triage
-- queue limited to roles that operationally need that content. Aggregate trend
-- access is a separate permission so Marketing/Analytics can consume privacy-
-- minimized metrics without inheriting the raw queue.
insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('feedback.trends.read','product','SENSITIVE',true,'Read aggregate feedback/NPS trends without user-authored free text')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,'feedback.trends.read'
from admin.roles r
where r.code in ('founder','super_admin','product','support','marketing','analytics')
on conflict do nothing;

delete from admin.role_permissions rp
using admin.roles r
where rp.role_id = r.id
  and rp.permission_code = 'feedback.read'
  and r.code in ('marketing','analytics');

create or replace function feedback.admin_trends(
  p_actor_account_id uuid,
  p_product_code text default null,
  p_days integer default 30
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,feedback,admin
as $$
declare v_items jsonb;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'feedback.trends.read') then
    raise exception 'feedback_permission_denied' using errcode='42501';
  end if;
  if p_days not between 1 and 365 then raise exception 'feedback_days_invalid' using errcode='22023'; end if;
  if p_product_code is not null and p_product_code !~ '^[a-z][a-z0-9_-]{1,39}$' then
    raise exception 'feedback_product_invalid' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.day desc,q.product_code,q.kind,q.status),'[]'::jsonb)
  into v_items
  from (
    select date_trunc('day',created_at)::date as day,product_code,kind::text as kind,status::text as status,
           count(*)::bigint as item_count,
           count(nps_score)::bigint as nps_response_count,
           case when count(nps_score)>0 then round(avg(nps_score)::numeric,2) else null end as average_nps
    from feedback.items
    where created_at>=now()-make_interval(days=>p_days)
      and (p_product_code is null or product_code=p_product_code)
    group by 1,2,3,4
  ) q;
  return jsonb_build_object('items',v_items,'days',p_days,'privacy',jsonb_build_object('freeTextIncluded',false));
end $$;

comment on function feedback.admin_list_items(uuid,text,text,text,text,integer,integer) is
  'Permission-checked triage queue. May contain bounded user-authored free text; do not grant feedback.read to aggregate-only roles.';

comment on function feedback.admin_trends(uuid,text,integer) is
  'Aggregate feedback/NPS trends guarded by feedback.trends.read. No free-text payload is returned.';

commit;
