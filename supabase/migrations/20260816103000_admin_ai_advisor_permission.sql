begin;

insert into admin.permissions(code,description)
values(
  'ai.advisor.read',
  'Use the internal read-only advisor over approved privacy-minimized read models'
)
on conflict (code) do update
set description=excluded.description;

-- Least privilege for the first release: only the founder and super-admin roles
-- receive the advisor capability automatically. Source-specific permissions are
-- still required at request time (for example analytics.read).
insert into admin.role_permissions(role_code,permission_code)
select role_code,'ai.advisor.read'
from (values('founder'),('super_admin')) as roles(role_code)
where exists(select 1 from admin.roles r where r.code=roles.role_code)
on conflict do nothing;

commit;
