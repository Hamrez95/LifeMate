-- Compatibility guard for the historical gift/referral/advocacy foundation migration.
-- Fresh databases reach this before the target tables exist, so it is a no-op.
-- During canonical migration reruns, remove only the policies that the historical
-- migration recreates with plain CREATE POLICY statements; the foundation migration
-- immediately recreates them with the same definitions.

do $$
begin
  if to_regclass('commerce.gift_intents') is not null then
    execute 'drop policy if exists lifemate_edge_runtime_gift_intents on commerce.gift_intents';
    execute 'drop policy if exists lifemate_admin_runtime_gift_intents on commerce.gift_intents';
  end if;

  if to_regclass('growth.referral_codes') is not null then
    execute 'drop policy if exists lifemate_edge_runtime_referral_codes on growth.referral_codes';
    execute 'drop policy if exists lifemate_admin_runtime_referral_codes on growth.referral_codes';
  end if;

  if to_regclass('growth.referral_attributions') is not null then
    execute 'drop policy if exists lifemate_edge_runtime_referral_attributions on growth.referral_attributions';
    execute 'drop policy if exists lifemate_admin_runtime_referral_attributions on growth.referral_attributions';
  end if;

  if to_regclass('growth.advocacy_submissions') is not null then
    execute 'drop policy if exists lifemate_edge_runtime_advocacy_submissions on growth.advocacy_submissions';
    execute 'drop policy if exists lifemate_admin_runtime_advocacy_submissions on growth.advocacy_submissions';
  end if;

  if to_regclass('growth.reward_rules') is not null then
    execute 'drop policy if exists lifemate_admin_runtime_reward_rules on growth.reward_rules';
  end if;

  if to_regclass('growth.reward_events') is not null then
    execute 'drop policy if exists lifemate_admin_runtime_reward_events on growth.reward_events';
  end if;
end
$$;
