\set ON_ERROR_STOP on

begin;

do $$
declare
  v_user uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_first jsonb;
  v_replay jsonb;
begin
  v_first := feedback.submit_item(
    v_user,'Feedback','wellmate','1.2.3','42',null,
    'Useful app',false,'feedback-contract-0001'
  );
  v_replay := feedback.submit_item(
    v_user,'Feedback','wellmate','1.2.3','42',null,
    'Useful app',false,'feedback-contract-0001'
  );
  if v_first->>'id' is distinct from v_replay->>'id' then
    raise exception 'exact replay must return the original feedback item';
  end if;

  begin
    perform feedback.submit_item(
      v_user,'Feedback','wellmate','1.2.4','42',null,
      'Useful app',false,'feedback-contract-0001'
    );
    raise exception 'changed app version reused an idempotency key';
  exception when unique_violation then null;
  end;

  begin
    perform feedback.submit_item(
      v_user,'Feedback','wellmate','1.2.3','43',null,
      'Useful app',false,'feedback-contract-0001'
    );
    raise exception 'changed build number reused an idempotency key';
  exception when unique_violation then null;
  end;

  begin
    perform feedback.submit_item(
      v_user,'Feedback','wellmate','1.2.3','42',null,
      'Useful app',true,'feedback-contract-0002'
    );
    raise exception 'ordinary feedback accepted advocacy opt-in';
  exception when invalid_parameter_value then null;
  end;
end
$$;

rollback;
