import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const requireText = (source, text, label) => {
  if (!source.includes(text)) throw new Error(`Missing ${label}: ${text}`);
};

const client = read('packages/lifemate_client/lib/src/legal_privacy_api.dart');
const ui = read('packages/lifemate_ui/lib/src/shared_legal_privacy.dart');
const composedGate = read('packages/lifemate_ui/lib/src/registration_experience_gate.dart');
const profile = read('packages/lifemate_ui/lib/src/shared_profile_with_privacy.dart');
const routes = read('supabase/functions/lifemate-api/legal_privacy_routes.ts');
const migration = read('supabase/migrations/20260826220500_legal_acceptance_privacy_preferences.sql');

for (const route of [
  '/api/v1/account/registration',
  '/api/v1/account/registration/legal-acceptance',
  '/api/v1/account/privacy-preferences',
]) requireText(client + routes, route, 'canonical route');

requireText(composedGate, 'LifeMateLegalRegistrationGate', 'mandatory legal gate composition');
requireText(ui, 'Nothing is pre-checked', 'non-prechecked legal copy');
requireText(ui, 'These choices are optional', 'optional preference copy');
requireText(ui, 'Security, transactional and care-reminder communications are separate from marketing', 'critical communication separation');
requireText(profile, "ValueKey('profile-privacy-preferences')", 'profile privacy entry point');
requireText(migration, 'check (actor_account_id = account_id)', 'self-only legal acceptance invariant');
requireText(migration, "default_enabled boolean not null default false", 'optional defaults off');
requireText(migration, 'consent.data_use_consents', 'canonical consent store reuse');

for (const forbidden of ['relationship', 'healthcare_permission', 'care_scope']) {
  if (client.includes(`'${forbidden}'`) || routes.includes(`'${forbidden}'`)) {
    throw new Error(`Legal/privacy client must not grant authorization: ${forbidden}`);
  }
}

console.log('Legal/privacy client integration contract passed.');
