begin;

alter table admin.approval_requests drop constraint if exists ck_admin_approval_before_size;
alter table admin.approval_requests add constraint ck_admin_approval_before_size
  check (octet_length(before_json::text) <= 16384);
alter table admin.approval_requests drop constraint if exists ck_admin_approval_delta_size;
alter table admin.approval_requests add constraint ck_admin_approval_delta_size
  check (octet_length(requested_delta_json::text) <= 16384);
alter table admin.approval_requests drop constraint if exists ck_admin_approval_after_size;
alter table admin.approval_requests add constraint ck_admin_approval_after_size
  check (octet_length(after_json::text) <= 16384);

comment on column admin.approval_requests.before_json is
'Redacted business-state snapshot only; raw health/contact/secret payloads are prohibited by the canonical API and payload size is database-bounded.';
comment on column admin.approval_requests.requested_delta_json is
'Redacted business-state delta only; child domains must store opaque IDs/codes/amount metadata rather than raw health/contact/free-text payloads.';
comment on column admin.approval_requests.after_json is
'Redacted requested after-state only; not a replacement for the child domain source of truth.';

commit;
