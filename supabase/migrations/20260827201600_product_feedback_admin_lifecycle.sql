begin;
create table if not exists feedback.item_audit (
 id bigint generated always as identity primary key, item_id uuid not null references feedback.items(id), actor_account_id uuid not null,
 action text not null check(action in ('Acknowledge','Triage','Resolve','LinkSupport','LinkProductIssue')), previous_status feedback.item_status not null, next_status feedback.item_status not null,
 reason text not null check(char_length(reason) between 3 and 500), created_at timestamptz not null default now());
alter table feedback.item_audit enable row level security; alter table feedback.item_audit force row level security; revoke all on feedback.item_audit from public,anon,authenticated;
create or replace function feedback.admin_transition_item(p_actor_account_id uuid,p_item_id uuid,p_expected_status feedback.item_status,p_action text,p_reason text,p_support_ticket_id uuid default null,p_product_issue_ref text default null) returns jsonb language plpgsql security definer set search_path=pg_catalog,feedback,admin as $$ declare v feedback.items%rowtype; v_next feedback.item_status; begin
 if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'support.write') then raise exception 'feedback_permission_denied' using errcode='42501'; end if;
 if nullif(btrim(p_reason),'') is null or char_length(btrim(p_reason)) not between 3 and 500 then raise exception 'feedback_reason_invalid' using errcode='22023'; end if;
 select * into v from feedback.items where id=p_item_id for update; if v.id is null then raise exception 'feedback_not_found' using errcode='P0002'; end if;
 if v.status is distinct from p_expected_status then raise exception 'feedback_status_conflict' using errcode='40001'; end if;
 v_next:=v.status;
 if p_action='Acknowledge' then if v.status<>'Submitted' then raise exception 'feedback_transition_invalid' using errcode='22023'; end if; v_next:='Acknowledged';
 elsif p_action='Triage' then if v.status not in ('Submitted','Acknowledged') then raise exception 'feedback_transition_invalid' using errcode='22023'; end if; v_next:='Triaged';
 elsif p_action='Resolve' then if v.status<>'Triaged' then raise exception 'feedback_transition_invalid' using errcode='22023'; end if; v_next:='Resolved';
 elsif p_action='LinkSupport' then if p_support_ticket_id is null then raise exception 'feedback_support_link_required' using errcode='22023'; end if;
 elsif p_action='LinkProductIssue' then if p_product_issue_ref is null or char_length(btrim(p_product_issue_ref))>160 then raise exception 'feedback_product_issue_invalid' using errcode='22023'; end if;
 else raise exception 'feedback_action_invalid' using errcode='22023'; end if;
 update feedback.items set status=v_next, linked_support_ticket_id=case when p_action='LinkSupport' then p_support_ticket_id else linked_support_ticket_id end, linked_product_issue_ref=case when p_action='LinkProductIssue' then btrim(p_product_issue_ref) else linked_product_issue_ref end, acknowledged_at=case when v_next='Acknowledged' then coalesce(acknowledged_at,now()) else acknowledged_at end, triaged_at=case when v_next='Triaged' then coalesce(triaged_at,now()) else triaged_at end, resolved_at=case when v_next='Resolved' then coalesce(resolved_at,now()) else resolved_at end, updated_at=now() where id=p_item_id;
 insert into feedback.item_audit(item_id,actor_account_id,action,previous_status,next_status,reason) values(p_item_id,p_actor_account_id,p_action,v.status,v_next,btrim(p_reason));
 return jsonb_build_object('itemId',p_item_id,'previousStatus',v.status,'status',v_next,'action',p_action); end $$;
revoke all on function feedback.admin_transition_item(uuid,uuid,feedback.item_status,text,text,uuid,text) from public,anon,authenticated;
grant usage on schema feedback to lifemate_admin_runtime; grant execute on function feedback.admin_transition_item(uuid,uuid,feedback.item_status,text,text,uuid,text) to lifemate_admin_runtime;
create or replace view admin.product_feedback_queue_v1 with(security_invoker=true) as select id,kind::text kind,status::text status,product_code,app_version,build_number,nps_score,advocacy_opt_in,linked_support_ticket_id,linked_product_issue_ref,created_at,acknowledged_at,triaged_at,resolved_at from feedback.items;
revoke all on admin.product_feedback_queue_v1 from public,anon,authenticated;
commit;
