import fs from 'node:fs';

const workflow = fs.readFileSync(
  '.github/workflows/identity-link-token-backfill.yml',
  'utf8',
);
const tool = fs.readFileSync(
  'tools/security/identity-link-token-backfill.ts',
  'utf8',
);

function fail(message) {
  console.error(`Identity-link backfill policy failure: ${message}`);
  process.exit(1);
}

function requireText(source, value, message) {
  if (!source.includes(value)) fail(message);
}

function rejectText(source, value, message) {
  if (source.includes(value)) fail(message);
}

for (const [value, message] of [
  ['  workflow_dispatch:', 'backfill must remain manual-only'],
  ['    environment: beta', 'backfill must be bound to protected beta Environment'],
  ["          test \"$GITHUB_REF\" = 'refs/heads/main'", 'backfill must require main ref'],
  ['          test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', 'backfill must require exact checked-out SHA'],
  ["          test \"${{ github.event.repository.private }}\" = 'true'", 'backfill must fail closed while repository is public'],
  ["          test \"${{ github.ref_protected }}\" = 'true'", 'backfill must fail closed while main is unprotected'],
  ["              test \"$LIFEMATE_IDENTITY_LINK_BACKFILL_CONFIRM\" = 'BACKFILL-IDENTITY-TOKENS'", 'apply mode must require exact human confirmation'],
  ['      LIFEMATE_IDENTITY_BACKFILL_DATABASE_URL: ${{ secrets.LIFEMATE_IDENTITY_BACKFILL_DATABASE_URL }}', 'database URL must come from beta-scoped secret'],
  ['      LIFEMATE_IDENTITY_LINK_KEY: ${{ secrets.LIFEMATE_IDENTITY_LINK_KEY }}', 'protective HMAC key must come from beta-scoped secret'],
  ['      LIFEMATE_IDENTITY_LINK_KEY_VERSION: ${{ secrets.LIFEMATE_IDENTITY_LINK_KEY_VERSION }}', 'key version must come from beta-scoped secret'],
  ['tools/security/identity-link-token-backfill.ts', 'workflow must execute the reviewed backfill tool'],
  ['raw provider subjects, token values, database URLs and key material are intentionally omitted', 'workflow summary must state the no-secret/no-identity evidence boundary'],
]) requireText(workflow, value, message);

for (const [value, message] of [
  ['on:\n  push:', 'backfill workflow must not execute automatically on push'],
  ['on:\n  pull_request:', 'backfill workflow must not execute automatically on pull requests'],
  ['actions/upload-artifact', 'backfill must not upload migration/token evidence artifacts'],
  ['echo "$LIFEMATE_IDENTITY_LINK_KEY"', 'workflow must never echo the identity-link key'],
  ['echo "$LIFEMATE_IDENTITY_BACKFILL_DATABASE_URL"', 'workflow must never echo the database URL'],
]) rejectText(workflow, value, message);

for (const [value, message] of [
  ['Backfill mode must be dry-run or apply.', 'tool must validate mode'],
  ['Identity-link backfill found one external identity mapped to multiple Accounts.', 'tool must fail closed on source conflicts'],
  ['Identity-link backfill conflicts with an existing token owned by another Account.', 'tool must fail closed on stored-token ownership conflicts'],
  ['if (mode === "dry-run")', 'tool must retain a no-write dry-run path'],
  ['await sql.begin(async (transaction) => {', 'apply path must remain transactional'],
  ['// Counts only. Never print raw subjects, tokens, DB URLs or key material.', 'CLI output must remain count-only'],
]) requireText(tool, value, message);

console.log(
  'Identity-link token backfill is manual, exact-main, beta-bound, private/protected fail-closed, transactional, and evidence-redacted.',
);
