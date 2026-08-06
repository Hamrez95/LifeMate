-- Cover foreign keys that are used for deletes, policy joins and operational
-- history queries. These indexes are intentionally narrow; unused-index lints on
-- a just-created schema are not evidence that query-path indexes should be removed.

create index if not exists ix_export_audit_requested_by_account
  on analytics.export_audit(requested_by_account_id)
  where requested_by_account_id is not null;

create index if not exists ix_entitlement_events_entitlement_time
  on commerce.entitlement_events(entitlement_id,recorded_at_utc desc);

create index if not exists ix_entitlements_feature
  on commerce.entitlements(feature_id,status,expires_at_utc);

create index if not exists ix_product_features_feature
  on commerce.product_features(feature_id,product_id);

create index if not exists ix_subscriptions_owner_account
  on commerce.subscriptions(owner_account_id,status)
  where owner_account_id is not null;

create index if not exists ix_subscriptions_product
  on commerce.subscriptions(product_id,status);

create index if not exists ix_subscriptions_plan
  on commerce.subscriptions(plan_id,status);

create index if not exists ix_consent_events_actor
  on consent.consent_events(actor_account_id,occurred_at_utc desc)
  where actor_account_id is not null;

create index if not exists ix_consent_records_actor
  on consent.consent_records(actor_account_id,created_at_utc desc)
  where actor_account_id is not null;

create index if not exists ix_consent_records_document
  on consent.consent_records(document_id,created_at_utc desc);

create index if not exists ix_data_use_consents_actor
  on consent.data_use_consents(actor_account_id,created_at_utc desc)
  where actor_account_id is not null;

create index if not exists ix_women_profiles_owner_person
  on lifemate.women_calendar_profiles(owner_person_id);

create index if not exists ix_women_episodes_owner_person_started
  on lifemate.women_calendar_episodes(owner_person_id,started_on desc,id);

create index if not exists ix_women_daily_owner_person_logged
  on lifemate.women_calendar_daily_logs(owner_person_id,logged_on desc,id);

create index if not exists ix_women_support_patient_person
  on lifemate.women_calendar_support_actions(patient_person_id,performed_at_utc desc,id);

create index if not exists ix_access_grants_grantor
  on security.access_grants(grantor_person_id,status)
  where grantor_person_id is not null;
