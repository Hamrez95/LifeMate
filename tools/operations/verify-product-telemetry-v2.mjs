import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const requireText = (source, text, label) => {
  if (!source.includes(text)) throw new Error(`Missing ${label}: ${text}`);
};

const migration = read('supabase/migrations/20260827115500_product_telemetry_v2_update_policy.sql');
const core = read('supabase/functions/lifemate-api/product_telemetry_v2.ts');
const routes = read('supabase/functions/lifemate-api/product_telemetry_v2_routes.ts');
const adminRoutes = read('supabase/functions/lifemate-admin-api/product_version_analytics_routes.ts');
const adminPathParser = read('supabase/functions/lifemate-admin-api/product_version_analytics.ts');
const adminService = read('supabase/functions/lifemate-admin-api/product_version_analytics_service.ts');

for (const table of [
  'analytics.product_version_presence',
  'platform.product_update_policies',
  'platform.product_update_policy_history',
]) requireText(migration, table, 'canonical telemetry/update-policy schema');

requireText(migration, 'analytics.account_product_version_v1', 'User 360 version read model');
requireText(migration, 'analytics.product_version_adoption_v1', 'aggregate version adoption read model');
requireText(migration, "mode varchar(16) not null default 'Soft'", 'soft-update default');
requireText(migration, "mode <> 'Force' or reason_code in ('Critical','Security','BreakingCompatibility')", 'force-update structural guardrail');
requireText(migration, "interval '400 days'", 'bounded retention');
requireText(routes, '/api/v1/product/version-presence', 'authenticated version-presence API');
requireText(routes, '/api/v1/product/update-policy', 'user update-policy API');
requireText(adminRoutes, '/api/v1/analytics/product-version-adoption', 'aggregate adoption Admin API');
requireText(adminPathParser, 'product-versions', 'User 360 version context Admin API');
requireText(adminRoutes, 'analytics.product_versions.read', 'Admin authorization');
requireText(adminService, 'source: "analytics.product_version_adoption_v1"', 'definition/source metadata');
requireText(core, 'product_version_field_forbidden', 'fingerprinting-field rejection');
requireText(core, 'forceUpdate: force', 'server update decision');

for (const forbidden of ['device_id', 'device_fingerprint', 'phone_number', 'email_address', 'health_payload']) {
  if (migration.toLowerCase().includes(forbidden)) {
    throw new Error(`Telemetry v2 must not introduce forbidden identifier/payload: ${forbidden}`);
  }
}

console.log('Product telemetry v2 source contract passed.');
