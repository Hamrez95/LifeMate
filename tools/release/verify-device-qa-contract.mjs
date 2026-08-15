import fs from 'node:fs';

const canonical = fs.readFileSync('docs/release/FOUNDATION_DEVICE_QA.md', 'utf8');
const compatibility = fs.readFileSync('wellmate/DEVICE_QA.md', 'utf8');

function requireText(source, value, label) {
  if (!source.includes(value)) {
    console.error(`Device QA contract failure: missing ${label}`);
    process.exit(1);
  }
}

for (const [value, label] of [
  ['exact `main` commit SHA', 'exact-main identity'],
  ['WellMate APK SHA-256', 'WellMate artifact hash'],
  ['CareMate APK SHA-256', 'CareMate artifact hash'],
  ['signing certificate SHA-256', 'signing certificate evidence'],
  ['APK-derived `minSdkVersion` and `targetSdkVersion`', 'Android SDK metadata'],
  ['reminder schedule is restored after device reboot', 'reboot reminder check'],
  ['reminder schedule is recalculated after timezone change', 'timezone reminder check'],
  ['reminder schedule remains valid after app update', 'app-update reminder check'],
  ['Persian / RTL', 'RTL QA'],
  ['English / LTR', 'LTR QA'],
  ['enlarged system text', 'text scaling QA'],
  ['unrelated account cannot see patient data', 'cross-user isolation'],
  ['patient revokes caregiver access', 'revocation QA'],
  ['privacy-safe telemetry', 'crash telemetry QA'],
  ['human evidence required', 'human-only gate'],
]) {
  requireText(canonical, value, label);
}

for (const stale of ['Draft PR #58', '0.9.0-internal.5+16', 'candidate API']) {
  if (canonical.includes(stale) || compatibility.includes(stale)) {
    console.error(`Device QA contract failure: stale candidate reference remains: ${stale}`);
    process.exit(1);
  }
}

requireText(
  compatibility,
  'docs/release/FOUNDATION_DEVICE_QA.md',
  'compatibility pointer to canonical checklist',
);

console.log('Physical-device QA contract is current and remains human-evidence-only.');
