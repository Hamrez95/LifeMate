-- Existing accounts already had a usable WellMate experience before V3.
-- Mark only rows present when this migration runs. On a fresh database there
-- are no rows yet, so future users still begin with NULL and see first-value
-- onboarding after account onboarding completes.
update lifemate.user_profiles
set wellmate_first_value_state = 'Completed'
where wellmate_first_value_state is null;
