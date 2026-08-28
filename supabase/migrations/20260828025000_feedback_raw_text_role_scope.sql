begin;

-- Raw user-authored feedback may contain sensitive free text. Keep the triage
-- queue limited to roles that operationally need that content. Marketing and
-- Analytics must consume aggregate trend contracts instead of inheriting raw
-- queue access merely because they analyze product signals.
delete from admin.role_permissions rp
using admin.roles r
where rp.role_id = r.id
  and rp.permission_code = 'feedback.read'
  and r.code in ('marketing','analytics');

comment on function feedback.admin_list_items(uuid,text,text,text,text,integer,integer) is
  'Permission-checked triage queue. May contain bounded user-authored free text; do not grant feedback.read to aggregate-only roles.';

comment on function feedback.admin_trends(uuid,text,integer) is
  'Aggregate feedback/NPS trends. No free-text payload is returned.';

commit;
