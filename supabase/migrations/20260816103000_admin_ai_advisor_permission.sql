begin;

insert into admin.permissions(
  code,
  domain,
  risk_level,
  role_assignable,
  description
)
values(
  'ai.advisor.read',
  'ai',
  'STANDARD',
  true,
  'Use the internal read-only advisor over approved privacy-minimized read models'
)
on conflict (code) do update
set
  domain = excluded.domain,
  risk_level = excluded.risk_level,
  role_assignable = excluded.role_assignable,
  description = excluded.description,
  updated_at_utc = now();

-- Least privilege for the first release: only the founder and super-admin roles
-- receive the advisor capability automatically. Source-specific permissions are
-- still required at request time (for example analytics.read).
insert into admin.role_permissions(role_id, permission_code)
select r.id, 'ai.advisor.read'
from admin.roles r
where r.code in ('founder', 'super_admin')
on conflict do nothing;

commit;
